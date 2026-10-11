import { createHandler } from './handler.mjs';
Deno.serve(createHandler({env:(name:string)=>Deno.env.get(name)}));
