const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('fs');
const path=require('path');
const root=path.resolve(__dirname,'../..');
const cb=fs.readFileSync(path.join(root,'real-cb-new-v9130-fix2.html'),'utf8');

test('CB camera modal hard-hides inactive live/edit controls',()=>{
  assert.ok(cb.includes('.camera-modal.hidden,.camera-modal .hidden{display:none!important}'));
  assert.ok(cb.includes('id="cameraEdit" class="camera-editor hidden"'));
  assert.ok(cb.includes('id="retakePhoto" class="secondary hidden"'));
  assert.ok(cb.includes('id="savePhoto" class="primary hidden"'));
});

test('CB camera uses one live viewport before capture and one preview viewport after capture',()=>{
  const fn=cb.slice(cb.indexOf('function showCameraStage('),cb.indexOf('async function configureCameraTrack'));
  assert.ok(fn.includes("$('cameraLive').classList.toggle('hidden',edit)"));
  assert.ok(fn.includes("$('cameraEdit').classList.toggle('hidden',!edit)"));
  assert.ok(fn.includes("$('capturePhoto').classList.toggle('hidden',edit)"));
  assert.ok(fn.includes("$('savePhoto').classList.toggle('hidden',!edit)"));
});

test('CB professional camera prefers rear high resolution and ImageCapture still photo',()=>{
  assert.ok(cb.includes("facingMode:{ideal:'environment'}"));
  assert.ok(cb.includes("width:{ideal:3840}"));
  assert.ok(cb.includes("height:{ideal:2160}"));
  assert.ok(cb.includes("'ImageCapture'in window?new ImageCapture(cam.track):null"));
  assert.ok(cb.includes("cam.imageCapture.takePhoto(settings)"));
  assert.ok(cb.includes("settings.imageWidth=Math.min(4096"));
  assert.ok(cb.includes("settings.imageHeight=Math.min(4096"));
});

test('CB camera enables continuous focus/exposure/white balance where supported',()=>{
  for(const token of ["focusMode:'continuous'","exposureMode:'continuous'","whiteBalanceMode:'continuous'"])assert.ok(cb.includes(token),token);
});

test('CB camera exposes hardware torch and hardware zoom only when supported',()=>{
  assert.ok(cb.includes("torch.hidden=!caps.torch"));
  assert.ok(cb.includes("if(zoomWrap&&zoom&&caps.zoom)"));
  assert.ok(cb.includes("applyConstraints({advanced:[{torch:cam.torch}]})"));
  assert.ok(cb.includes("applyConstraints({advanced:[{zoom:v}]})"));
});

test('CB saved colour image is 1200 square high quality JPEG with mild colour-preserving tone',()=>{
  assert.ok(cb.includes("const canvas=$('cropCanvas'),ctx=canvas.getContext('2d'),size=1200"));
  assert.ok(cb.includes("brightness=Math.max(.98,Math.min(1.08"));
  assert.ok(cb.includes("contrast=Math.max(.98,Math.min(1.06"));
  assert.ok(cb.includes("'image/jpeg',.94"));
});
