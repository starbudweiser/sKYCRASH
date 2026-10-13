import { defineConfig } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

// Socle est lu directement depuis sa copie locale : la preview suit ses mises à jour.
const SOCLE = "/Volumes/SKYRIM/TOOLS/DESIGN/Socle";

// Build : un seul index.html autonome dans ../dist (comme la preview d'origine).
export default defineConfig({
  plugins: [viteSingleFile()],
  resolve: { alias: { "@socle": SOCLE } },
  server: { port: Number(process.env.PORT) || 5180, strictPort: true, fs: { allow: [".", SOCLE] } },
  build: { outDir: "../dist", emptyOutDir: false },
});
