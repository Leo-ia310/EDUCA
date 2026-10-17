// Real HTTP/Auth/PostgREST checks. All temporary accounts are deleted in finally.
// Uses admin.createUser (confirmed email); never sends invitations or email.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { createApp } from "../src/app";
import { requireSupabaseServiceRole } from "../src/lib/supabase";

async function main() {
  const db = requireSupabaseServiceRole();
  const suffix = crypto.randomUUID();
  const password = `Task26-${crypto.randomBytes(16).toString("hex")}!`;
  const emails = ["owner", "admin", "coordinator"].map(role => `task26.${role}.${suffix}@example.com`);
  const server = createApp().listen(0, "127.0.0.1");
  await new Promise<void>(resolve => server.once("listening", resolve));
  const address = server.address() as { port: number };
  const api = `http://127.0.0.1:${address.port}/api`;
  let ownerAuthId: string | undefined;
  async function call(path: string, body?: unknown, token?: string) {
    const response = await fetch(api + path, {
      method: body === undefined ? "GET" : "POST",
      headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const json = await response.json() as any;
    return { status: response.status, json };
  }
  try {
    const institution = await db.from("institutions").select("id").eq("active", true).is("deleted_at", null).limit(1).single();
    assert.ifError(institution.error);
    const institutionId = Number(institution.data.id);
    const role = await db.from("roles").select("id").eq("code", "admin").is("institution_id", null).eq("active", true).single();
    assert.ifError(role.error);
    const owner = await db.auth.admin.createUser({ email: emails[0], password, email_confirm: true, app_metadata: { institution_id: institutionId, roles: ["admin"] } });
    assert.ifError(owner.error);
    ownerAuthId = owner.data.user.id;
    const user = await db.from("users").insert({ auth_user_id: ownerAuthId, institution_id: institutionId, full_name: "Temporary Task 26 owner", email: emails[0] }).select("id").single();
    assert.ifError(user.error);
    const assigned = await db.from("user_roles").insert({ user_id: user.data.id, role_id: role.data.id, institution_id: institutionId });
    assert.ifError(assigned.error);
    const ownerLogin = await call("/auth/login", { username: emails[0], password });
    assert.equal(ownerLogin.status, 200, JSON.stringify(ownerLogin.json));
    const ownerToken = ownerLogin.json.data.session.accessToken;
    for (const [index, code] of ["admin", "coordinator"].entries()) {
      const permissions = ["dashboard.view", "students.view"];
      const created = await call("/admin/profiles", { email: emails[index + 1], password, fullName: `Temporary Task 26 ${code}`, roleCode: code, permissions }, ownerToken);
      assert.equal(created.status, 201, JSON.stringify(created.json));
      assert.equal(created.json.data.profile.roleCode, code);
      assert.deepEqual(created.json.data.profile.permissions, permissions);
      const login = await call("/auth/login", { username: emails[index + 1], password });
      assert.equal(login.status, 200, JSON.stringify(login.json));
      assert.deepEqual(login.json.data.user.roles, [code]);
      assert.deepEqual(login.json.data.user.adminPermissions, permissions);
      const token = login.json.data.session.accessToken;
      const allowed = await call("/admin/directory", undefined, token);
      assert.equal(allowed.status, 200, JSON.stringify(allowed.json));
      const denied = await call("/admin/profiles", undefined, token);
      assert.equal(denied.status, 403, "Must not grant roles.view implicitly");
      console.log(`${code}: created, permissions persisted, login and allowed/denied admin routes passed`);
    }
  } finally {
    const rows = await db.from("users").select("auth_user_id").in("email", emails);
    assert.ifError(rows.error);
    const ids = new Set<string>(rows.data.map((row: any) => row.auth_user_id));
    if (ownerAuthId) ids.add(ownerAuthId);
    for (const id of ids) {
      const deleted = await db.auth.admin.deleteUser(id);
      assert.ifError(deleted.error);
    }
    const remaining = await db.from("users").select("id").in("email", emails);
    assert.ifError(remaining.error);
    assert.equal(remaining.data.length, 0, "Temporary accounts must be removed");
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    console.log("Temporary accounts removed; no emails sent.");
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
