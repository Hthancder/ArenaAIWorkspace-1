import { build } from 'esbuild';
import { mkdir, readFile } from 'node:fs/promises';
const metadata = `// ==UserScript==
// @name         Duality Client Reborn (compatibility preview)
// @namespace    arena.survev.reborn
// @version      0.4.0
// @description  Lightweight menu, validated semantic discovery, bounded hooks and reversible features. Live compatibility unverified.
// @match        https://survev.io/*
// @match        https://*.survev.io/*
// @run-at       document-start
// @grant        none
// @inject-into  page
// @sandbox      raw
// @noframes
// ==/UserScript==`;
const acornLicense = await readFile('node_modules/acorn/LICENSE', 'utf8');
await mkdir('userscripts', { recursive: true });
await build({ entryPoints: ['src/main.mjs'], outfile: 'userscripts/duality-reborn.user.js', bundle: true,
  format: 'iife', target: 'es2022', legalComments: 'inline', minify: false, keepNames: true,
  banner: { js: metadata + '\n/*! Bundled parser: Acorn.\n' + acornLicense + '\n*/' }, charset: 'utf8' });
console.log('Built userscripts/duality-reborn.user.js');
