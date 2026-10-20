type ChargeStatusRow = {
    status?: unknown;
    due_at?: unknown;
    institutions?: {
        timezone?: string | null;
    } | null;
};
const formatters = new Map<string, Intl.DateTimeFormat>();
/** Billing due dates are calendar days in the school's timezone. */
export function effectiveChargeStatus(charge: ChargeStatusRow, now = new Date()) {
    const stored = String(charge.status ?? "pending");
    if (stored === "paid" || stored === "cancelled" || charge.due_at == null)
        return stored;
    const zone = charge.institutions?.timezone ?? "America/Managua";
    let formatter = formatters.get(zone);
    if (!formatter) {
        formatter = new Intl.DateTimeFormat("en", { timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit" });
        if (formatters.size >= 32)
            formatters.clear();
        formatters.set(zone, formatter);
    }
    const parts = formatter.formatToParts(now);
    const value = (type: string) => parts.find(part => part.type === type)!.value;
    const today = `${value("year")}-${value("month")}-${value("day")}`;
    return String(charge.due_at).slice(0, 10) < today ? "overdue" : stored;
}
