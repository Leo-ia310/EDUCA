import { HttpError } from "./errors";

export type PageOptions = {
  page: number;
  pageSize: number;
  from: number;
  to: number;
};

export type PageResult<T> = {
  items: T[];
  pageInfo: {
    page: number;
    pageSize: number;
    total: number;
    totalPages: number;
    hasNextPage: boolean;
    hasPreviousPage: boolean;
  };
};

const DEFAULT_PAGE_SIZE = 50;
const MAX_PAGE_SIZE = 100;

export function paginationFromQuery(
  query: Record<string, unknown>,
  defaults: { pageSize?: number; maxPageSize?: number } = {},
): PageOptions {
  const maxPageSize = defaults.maxPageSize ?? MAX_PAGE_SIZE;
  const page = positiveInteger(query.page, "Página", 1);
  const pageSize = Math.min(
    positiveInteger(query.pageSize ?? query.limit, "Tamaño de página", defaults.pageSize ?? DEFAULT_PAGE_SIZE),
    maxPageSize,
  );
  const from = (page - 1) * pageSize;
  return { page, pageSize, from, to: from + pageSize - 1 };
}

export function paged<T>(
  items: T[],
  count: number | null | undefined,
  page: PageOptions,
): PageResult<T> {
  const total = count ?? items.length;
  const totalPages = total === 0 ? 0 : Math.ceil(total / page.pageSize);
  return {
    items,
    pageInfo: {
      page: page.page,
      pageSize: page.pageSize,
      total,
      totalPages,
      hasNextPage: page.page < totalPages,
      hasPreviousPage: page.page > 1,
    },
  };
}

export function singlePage<T>(items: T[]): PageResult<T> {
  return {
    items,
    pageInfo: {
      page: 1,
      pageSize: items.length,
      total: items.length,
      totalPages: items.length === 0 ? 0 : 1,
      hasNextPage: false,
      hasPreviousPage: false,
    },
  };
}

function positiveInteger(value: unknown, label: string, fallback: number) {
  if (value == null || value === "") return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new HttpError(400, `${label} inválido.`, "validation_error");
  }
  return parsed;
}
