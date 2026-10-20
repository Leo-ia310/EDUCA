import { scrypt } from "node:crypto";
import { promisify } from "node:util";
import { HttpError } from "../../lib/errors";
import { requireSupabaseServiceRole } from "../../lib/supabase";
import { AdminRepository } from "./admin.repository";
const deriveProof = promisify(scrypt);
type ProvisionRepository = Pick<AdminRepository, "beginProvision" | "completeProvision" | "observeProvision" | "rejectProvision">;
export class AccountProvisioningService {
    constructor(private readonly repository: ProvisionRepository, private readonly authClient: () => any = requireSupabaseServiceRole) { }
    async create(institutionId: number, kind: string, key: string, payload: Record<string, unknown>, password: string) {
        const proof = (await deriveProof(password, key, 32) as Buffer).toString("hex");
        const job = await this.repository.beginProvision(institutionId, kind, key, payload, proof);
        if (job.status === 'completed')
            return job.result;
        const auth = this.authClient().auth.admin;
        const check = async () => {
            let result: any;
            try {
                result = await auth.getUserById(job.authUserId);
            }
            catch {
                throw pending();
            }
            if (result.error) {
                if (result.error.status === 404 || result.error.code === 'user_not_found')
                    return null;
                throw pending();
            }
            if (!result.data?.user)
                throw pending();
            const user = result.data.user;
            if (user.id !== job.authUserId || user.app_metadata?.provisioning_id !== job.id ||
                String(user.app_metadata?.institution_id) !== String(institutionId) || user.email?.toLowerCase() !== job.email) {
                throw new HttpError(409, "La identidad reservada requiere revisión administrativa.", "provisioning_review");
            }
            return user;
        };
        let user = await check();
        if (!user) {
            const account = payload.account as Record<string, unknown>;
            const role = kind === 'profile' ? String(payload.roleCode) : ({ students: 'student', teachers: 'teacher', parents: 'parent' } as Record<string, string>)[kind];
            let created: any;
            try {
                created = await auth.createUser({ id: job.authUserId, email: job.email, password, email_confirm: true,
                    user_metadata: { full_name: account.full_name },
                    app_metadata: { institution_id: institutionId, roles: [role], provisioning_id: job.id, provider: 'email', providers: ['email'] } });
            }
            catch {
                throw pending();
            }
            if (created.error || !created.data?.user) {
                user = await check(); // A concurrent attempt or lost response may have succeeded.
                if (!user) {
                    const status = created.error?.status;
                    if ((status === 400 || status === 422) && await this.repository.rejectProvision(job.id)) {
                        throw new HttpError(400, "Auth rechazó los datos de acceso. Revisa el correo y la contraseña y usa una nueva solicitud.", "auth_user_create_failed");
                    }
                    throw pending();
                }
            }
            else {
                user = created.data.user;
                await this.repository.observeProvision(job.id, user.id);
                if (user.id !== job.authUserId || user.app_metadata?.provisioning_id !== job.id ||
                    String(user.app_metadata?.institution_id) !== String(institutionId) || user.email?.toLowerCase() !== job.email) {
                    throw new HttpError(409, "La identidad creada requiere revisión administrativa.", "provisioning_review");
                }
            }
        }
        // No blind delete on failure: a missing SQL response can mean commit succeeded.
        // The reserved UUID and request remain durable and the next attempt resumes.
        return this.repository.completeProvision(job.id);
    }
}
function pending() { return new HttpError(503, "No se pudo confirmar el alta. Reintenta con la misma solicitud.", "provisioning_pending"); }
