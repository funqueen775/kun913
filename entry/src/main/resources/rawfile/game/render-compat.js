// Work around ArkWeb/emulator uniform-block reflection returning mangled names + NUL.
(() => {
  if (!window.WebGL2RenderingContext) return;
  const proto = WebGL2RenderingContext.prototype;
  const getIndex = proto.getUniformBlockIndex;
  const namesByContext = new WeakMap();
  const clean = name => (name || '').replace(/\0+$/, '');
  function translatedName(gl, name) {
    let names = namesByContext.get(gl);
    if (!names) { names = new Map(); namesByContext.set(gl, names); }
    if (names.has(name)) return names.get(name);
    const vs = gl.createShader(gl.VERTEX_SHADER);
    const fs = gl.createShader(gl.FRAGMENT_SHADER);
    const program = gl.createProgram();
    if (!vs || !fs || !program) {
      if (program) gl.deleteProgram(program);
      if (vs) gl.deleteShader(vs);
      if (fs) gl.deleteShader(fs);
      return '';
    }
    let translated = '';
    try {
      gl.shaderSource(vs, '#version 300 es\nlayout(std140) uniform ' + name + ' { vec4 ct_probe; };\nvoid main(){ gl_Position = ct_probe; }');
      gl.shaderSource(fs, '#version 300 es\nprecision mediump float;\nout vec4 ct_color;\nvoid main(){ ct_color = vec4(1.0); }');
      gl.compileShader(vs); gl.compileShader(fs);
      gl.attachShader(program, vs); gl.attachShader(program, fs); gl.linkProgram(program);
      if (gl.getProgramParameter(program, gl.LINK_STATUS) && gl.getProgramParameter(program, gl.ACTIVE_UNIFORM_BLOCKS) === 1) {
        translated = clean(gl.getActiveUniformBlockName(program, 0));
      }
    } finally {
      gl.deleteProgram(program); gl.deleteShader(vs); gl.deleteShader(fs);
    }
    names.set(name, translated);
    return translated;
  }
  proto.getUniformBlockIndex = function (program, name) {
    const result = getIndex.call(this, program, name);
    if (result !== this.INVALID_INDEX || !/^[A-Za-z_]\w*$/.test(name)) return result;
    const count = this.getProgramParameter(program, this.ACTIVE_UNIFORM_BLOCKS);
    if (!count) return result;
    const active = Array.from({ length: count }, (_, i) => this.getActiveUniformBlockName(program, i));
    if (!active.some(value => /^webgl_[a-f0-9]+\0+$/.test(value))) return result;
    // Do not resurrect blocks optimized out or absent in this shader variant.
    const declaration = new RegExp('\\buniform\\s+' + name + '\\s*\\{');
    if (!this.getAttachedShaders(program).some(shader => declaration.test(this.getShaderSource(shader)))) return result;
    const translated = translatedName(this, name);
    const index = translated ? active.findIndex(value => clean(value) === translated) : -1;
    if (index >= 0) {
      console.info('CT_COMPAT restored uniform block ' + name + ' at index ' + index);
      return index;
    }
    return result;
  };
})();
