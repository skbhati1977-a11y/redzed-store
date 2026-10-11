const {test}=require('node:test');
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const {verifyGithubOidc,resetKeyCache,AUDIENCE}=require('../api/_github-oidc');
const {privateKey,publicKey}=crypto.generateKeyPairSync('rsa',{modulusLength:2048});
const repository='skbhati1977-a11y/redzed-store',ref='refs/heads/test71-real-chat-e2e-finalization';
function signed(workflow_ref){const now=Math.floor(Date.now()/1000);const head=Buffer.from(JSON.stringify({alg:'RS256',kid:'probe'})).toString('base64url');const payload=Buffer.from(JSON.stringify({iss:'https://token.actions.githubusercontent.com',aud:AUDIENCE,repository,ref,workflow_ref,iat:now,exp:now+60})).toString('base64url');return `${head}.${payload}.${crypto.sign('RSA-SHA256',Buffer.from(`${head}.${payload}`),privateKey).toString('base64url')}`;}
const keys=async()=>({ok:true,json:async()=>({keys:[{...publicKey.export({format:'jwk'}),kid:'probe'}]})});
test('focused financial workflow receives only branch-scoped runner identity',async()=>{resetKeyCache();const id=await verifyGithubOidc(signed(`${repository}/.github/workflows/test71-financial-readiness.yml@${ref}`),keys);assert.equal(id.ref,ref);});
test('workflow suffixes and unrelated workflows fail exact allowlist',async()=>{for(const workflow of [`${repository}/.github/workflows/test71-checkpoint0-e2e.yml@${ref}-suffix`,`${repository}/.github/workflows/other.yml@${ref}`]){resetKeyCache();await assert.rejects(verifyGithubOidc(signed(workflow),keys),/Invalid runner identity/);}});
