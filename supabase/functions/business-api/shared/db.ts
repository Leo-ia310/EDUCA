import { HttpError } from "./http.ts";

type QueryLike<T> = PromiseLike<{
  data: T | null;
  error: { message: string } | null;
}>;

export async function expectSingle<T>(
  query: QueryLike<T>,
  message: string,
) {
  const { data, error } = await query;
  if (error || data == null) {
    throw new HttpError(400, error?.message ?? message, "db_error");
  }
  return data;
}
