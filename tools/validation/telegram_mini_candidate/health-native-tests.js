const fs=require('fs'),cp=require('child_process'),assert=require('assert'),crypto=require('crypto'),path=require('path');
const out=process.argv[2],exe=path.resolve(out,'mini_health_snapshot.exe'),checks=[];
const base=fs.mkdtempSync('/tmp/uos-mini-health-test-');fs.chmodSync(base,0o700);
function write(p,s){const f=path.join(base,p);fs.mkdirSync(path.dirname(f),{recursive:true});fs.writeFileSync(f,String(s));}
function run(args=[]){const r=cp.spawnSync(exe,args,{encoding:'utf8',timeout:3000,maxBuffer:65536});return {exit:r.status,stdout:r.stdout,stderr:r.stderr};}
function snapshot(){const r=run(['--fixture',base]);assert.equal(r.exit,0,r.stderr);return JSON.parse(r.stdout);}
function temperature(){return snapshot().devices.find(x=>x.id==='temperature:hwmon0:temp1');}
write('class/hwmon/hwmon0/name','fixture');
write('class/hwmon/hwmon0/temp1_input','30000');write('class/hwmon/hwmon0/temp1_max','50000');write('class/hwmon/hwmon0/temp1_crit','80000');
write('class/net/eth0/operstate','up');write('class/net/eth0/carrier','1');
write('block/testdisk/size','2048');write('block/testdisk/device/state','running');
write('block/loop0/size','100');
let s=snapshot();assert(s.complete);assert.equal(s.devices.length,3);assert.equal(s.excluded_virtual_blocks,1);assert.equal(temperature().grade,'normal');checks.push('enumerates_actual_fixture_and_excludes_virtual_loop');
write('class/hwmon/hwmon0/temp1_input','50000');assert.equal(temperature().grade,'warning');
write('class/hwmon/hwmon0/temp1_input','80000');assert.equal(temperature().grade,'critical');checks.push('changed_measurements_and_exact_thresholds');
write('class/hwmon/hwmon0/temp1_max','90000');assert.equal(temperature().grade,'unknown');assert.equal(temperature().state,'inconsistent_thresholds');checks.push('incoherent_thresholds_not_healthy');
write('class/hwmon/hwmon0/temp1_input','not-a-number');assert.equal(temperature().reading,null);assert.equal(temperature().grade,'unknown');checks.push('invalid_reading_unknown');
write('class/hwmon/hwmon0/temp1_input','x'.repeat(513));assert.equal(temperature().reading,null);checks.push('bounded_attribute');
write('class/hwmon/hwmon0/temp1_input','30000');write('class/hwmon/hwmon0/temp1_max','50000');
for(const value of ['0','255000','invalid']) {write('class/hwmon/hwmon0/temp1_max',value);assert.equal(temperature().grade,'unknown');assert.equal(temperature().state,'invalid_thresholds');assert.equal(temperature().thresholds_valid,false);}
write('class/hwmon/hwmon0/temp1_max','50000');checks.push('invalid_thresholds_never_normal');
write('class/hwmon/hwmon1/name','drivetemp');write('class/hwmon/hwmon1/temp1_input','90000');
s=snapshot();assert.equal(s.devices.find(x=>x.id==='sensor:hwmon1').state,'not_sampled');assert(!s.devices.some(x=>x.id.startsWith('temperature:hwmon1')));fs.renameSync(base+'/class/hwmon/hwmon1',base+'/excluded-driver');checks.push('disk_temperature_driver_not_sampled');
write('class/hwmon/hwmon0/temp1_max','0');write('class/hwmon/hwmon0/temp1_input','90000');assert.equal(temperature().grade,'critical');write('class/hwmon/hwmon0/temp1_max','50000');write('class/hwmon/hwmon0/temp1_input','30000');checks.push('valid_critical_alert_survives_invalid_high');
write('class/net/veth:one/operstate','up');write('class/net/veth:one/carrier','1');assert(snapshot().devices.some(x=>x.id==='network:veth:one'));fs.renameSync(base+'/class/net/veth:one',base+'/special-interface');checks.push('safe_linux_component_characters');
write('class/hwmon/hwmon0/temp1_label',' ');assert(temperature().label.endsWith('temp1'));checks.push('empty_label_fallback');
write('class/hwmon/hwmon0/serial','SYNTHETIC_NEVER_READ_SERIAL');assert(!JSON.stringify(snapshot()).includes('NEVER_READ'));checks.push('serial_not_collected');
const outside=base+'-outside';fs.writeFileSync(outside,'SYNTHETIC_OUTSIDE_SECRET');fs.symlinkSync(outside,base+'/class/hwmon/hwmon0/temp2_input');
s=snapshot();assert.equal(s.devices.find(x=>x.id.endsWith(':temp2')).reading,null);assert(!JSON.stringify(s).includes('OUTSIDE_SECRET'));checks.push('symlink_escape_refused');
cp.execFileSync('/usr/bin/mkfifo',[base+'/class/hwmon/hwmon0/temp3_input']);s=snapshot();assert.equal(s.devices.find(x=>x.id.endsWith(':temp3')).reading,null);checks.push('fifo_not_read_or_blocked');
write('class/net/eth0/operstate','down');write('class/net/eth0/carrier','0');assert.equal(snapshot().devices.find(x=>x.kind==='network').grade,'unknown');assert.equal(snapshot().devices.find(x=>x.kind==='block').grade,'unknown');checks.push('link_and_disk_state_not_health_scores');
fs.renameSync(base+'/class/hwmon',base+'/class/hwmon-absent');s=snapshot();assert(!s.complete);assert.equal(s.devices.length,2);checks.push('missing_inventory_explicit_partial');
fs.renameSync(base+'/class/hwmon-absent',base+'/class/hwmon');
for(let i=4;i<=65;i++)write('class/hwmon/hwmon0/temp'+i+'_input','30000');
const bounded=snapshot();assert.equal(bounded.devices.length,64);assert.equal(bounded.truncated,true);assert.equal(bounded.complete,false);assert.equal(bounded.excluded_virtual_blocks,null);checks.push('device_count_limit_explicit_partial');
assert.notEqual(run(['--fixture','/tmp']).exit,0);assert.notEqual(run(['--anything']).exit,0);checks.push('closed_native_arguments');
const live=run();assert.equal(live.exit,0,live.stderr);const observed=JSON.parse(live.stdout);assert.equal(observed.source,'linux_sysfs');assert(observed.devices.length>0);fs.writeFileSync(out+'/health-live-native.json',JSON.stringify(observed,null,2));checks.push('actual_host_sysfs_observed');
fs.writeFileSync(out+'/health-native-tests.json',JSON.stringify({status:'PASS',at:new Date().toISOString(),checks,fixture:base,live_devices:observed.devices.length,worker_sha256:crypto.createHash('sha256').update(fs.readFileSync(exe)).digest('hex')},null,2));console.log({checks:checks.length,live_devices:observed.devices.length});
