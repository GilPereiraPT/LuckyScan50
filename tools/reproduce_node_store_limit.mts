import {mkdtemp, readdir, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
const folder=await mkdtemp(join(tmpdir(),'luckyscan-node-isolated-'));
process.env.RESULTS_PATH=join(folder,'results.json');
const {importResult,allResults}=await import('../backend/src/data/store.ts');
const signatures=[[5,2],[5,1],[5,0],[4,2],[4,1],[3,2],[4,0],[2,2],[3,1],[3,0],[1,2],[2,1],[2,0]];
const row=(id:string)=>({game:'euromilhoes',drawId:id,date:'2026-01-02',status:'complete',sourceUrl:'https://example.org/fixture',retrievedAt:'2026-01-03T09:00:00Z',numbers:[1,2,3,4,5],stars:[1,2],tiers:signatures.map(([main,stars],i)=>({tier:i+1,main,stars,amountCents:100,winnersPortugal:0,winnersTotal:1}))});
try {
  let lost=0;
  for(let i=0;i<10;i++){
    await writeFile(process.env.RESULTS_PATH,'[]');
    await Promise.all([importResult(row('001/2026')),importResult(row('002/2026'))]);
    if((await allResults()).length!==2)lost++;
  }
  console.log('Concurrent lost-update trials:',lost,'/ 10');
  await writeFile(process.env.RESULTS_PATH,'[]');
  await importResult(row('001/2026'));
  const changed=row('001/2026');changed.numbers=[1,2,3,4,6];
  await importResult(changed);
  console.log('Confirmed key after second import:',(await allResults())[0].numbers);
  console.log('Files retained:',await readdir(folder));
} finally {await rm(folder,{recursive:true,force:true});}
