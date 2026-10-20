import { assertNoDbError } from "./db";
type Page<T> = PromiseLike<{
    data: T[] | null;
    error: {
        message: string;
    } | null;
}>;
/** For bounded domain exports/grids that require every matching row. Supply a
 * fresh, deterministically ordered query for each page. Public list endpoints
 * should use pagination instead. Advance by rows received: a server can cap a
 * page below our requested size. A short page does not prove end of results. */
export async function readAllPages<T>(query: (from: number, to: number) => Page<T>) {
    const rows: T[] = [];
    const size = 500;
    for (;;) {
        const { data, error } = await query(rows.length, rows.length + size - 1);
        assertNoDbError(error);
        if (!data?.length)
            return rows;
        rows.push(...data);
    }
}
