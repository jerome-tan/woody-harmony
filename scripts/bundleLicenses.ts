import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import type { Plugin } from 'vite'

// Renderer dependencies are bundled, so their node_modules directories are not
// shipped. Keep their license and notice files alongside the compiled renderer.
export function bundleLicenses(): Plugin {
  return {
    name: 'bundled-dependency-licenses',
    apply: 'build',
    generateBundle(_options, bundle) {
      const packageDirs = new Set<string>()
      for (const output of Object.values(bundle)) {
        if (output.type !== 'chunk') continue
        for (const id of Object.keys(output.modules)) {
          if (id.startsWith('\0')) continue
          const match = id.replaceAll('\\', '/').match(/^(.*\/node_modules\/(?:@[^/]+\/)?[^/]+)/)
          if (match) packageDirs.add(match[1])
        }
      }

      const sections: string[] = ['Third-party licenses for the bundled renderer.']
      for (const dir of [...packageDirs].sort()) {
        const pkg = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8'))
        const files: string[] = []
        for (const entry of readdirSync(dir, { withFileTypes: true })) {
          if (entry.isFile() && /^(licen[cs]e|notice|copying)(?:[.-].*)?$/i.test(entry.name)) {
            files.push(entry.name)
          } else if (entry.isDirectory() && /^licen[cs]es$/i.test(entry.name)) {
            // ECharts also includes third-party notices under licenses/.
            for (const name of readdirSync(join(dir, entry.name))) {
              files.push(join(entry.name, name))
            }
          }
        }
        sections.push(`\n=== ${pkg.name}@${pkg.version} (${pkg.license ?? 'see below'}) ===`)
        if (files.length === 0) {
          // Some published packages (e.g. icons-svg) only carry license metadata.
          const repository = typeof pkg.repository === 'string' ? pkg.repository : pkg.repository?.url
          sections.push(`No license text shipped in this npm package.\nSource: ${repository ?? pkg.homepage ?? pkg.name}`)
        }
        for (const file of files.sort()) {
          sections.push(`\n--- ${file.replaceAll('\\', '/')} ---\n${readFileSync(join(dir, file), 'utf8')}`)
        }
      }
      this.emitFile({ type: 'asset', fileName: 'THIRD_PARTY_LICENSES.txt', source: sections.join('\n') })
    }
  }
}
