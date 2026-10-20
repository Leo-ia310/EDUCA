export class HttpError extends Error {
  constructor(readonly status:number,message:string,readonly code="business_error",readonly retryAfter?:number){super(message);}
}
export function isHttpError(error:unknown):error is HttpError{return error instanceof HttpError;}
