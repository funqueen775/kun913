import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    // 后端：backend/engine_core（M4 才接 FastAPI），前端只上报原始行为，见《后端开发方案 V1》§1
    // M4 之前 /api 没有可代理的服务，请求失败是预期状态
    proxy: {
      '/api': { target: 'http://127.0.0.1:8000', changeOrigin: true },
    },
  },
})
