import {databaseError,type DatabaseError} from "./database-error";
import {HttpError} from "./errors";
type QueryLike<T>=PromiseLike<{data:T|null;error:DatabaseError|null}>;
export async function expectSingle<T>(query:QueryLike<T>,message:string){
 const {data,error}=await query;
 if(error)throw databaseError(error);
 if(data==null)throw new HttpError(404,message,"not_found");
 return data;
}
export function assertNoDbError(error:DatabaseError|null|undefined){if(error)throw databaseError(error);}
