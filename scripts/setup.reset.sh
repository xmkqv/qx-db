rm -rf node_modules
rm pnpm-lock.yaml
pnpm i
pnpm dlx jsr add -D @ryoppippi/unplugin-typia
pnpm install typia
pnpm typia setup --manager pnpm
npx depcheck --ignores="vite*,playwright*,@solid-primitives/*"
npm run dev