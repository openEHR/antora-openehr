'use strict'

// Rewrites links to the legacy specifications site into links to the page on this site.
//
// Spec sources link other documents through {openehr_*} attributes (resources/global-vars.yml)
// and hardcoded URLs, both of the form
//   https://specifications.openehr.org/releases/<COMPONENT>/<VERSION>/<DOC>.html[#<anchor>]
// The legacy <DOC> is a module of the same name here (AM/latest/AOM2.html -> AM:AOM2).
// After conversion, each such link becomes a relative link to:
//   - the module page that has the anchor as an id (legacy documents are split into
//     one page per chapter), else
//   - the module's index page.
// <VERSION> "latest" is the component's latest version, "development" the development
// version, anything else is used as the version name when it exists, else latest.
// Links that match no component or module (UML, ITS-JSON) are left as they are and counted
// in the log. Deeper paths (CNF test files, /components/, wiki) do not match and are left too.

const path = require('path')

const LEGACY_LINK =
  /<a\b([^>]*?)\bhref="https?:\/\/(?:www\.)?specifications\.openehr\.org\/releases\/([A-Za-z0-9_-]+)\/([^/"#]+)\/([^/"#]*?)(?:\.html)?(#[^"]*)?"([^>]*)>/g

// Section id as Asciidoctor generates it with idprefix '_' and idseparator '_'.
const toId = (text) =>
  '_' +
  text
    .toLowerCase()
    .replace(/&[a-z0-9#]+;/g, '')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')

// A malformed %-escape in an anchor must not stop the build: use the anchor as written.
const safeDecode = (text) => {
  try {
    return decodeURIComponent(text)
  } catch {
    return text
  }
}

module.exports.register = function () {
  const logger = this.getLogger('rewrite-legacy-spec-links')

  this.on('documentsConverted', ({ contentCatalog }) => {
    const pages = contentCatalog.getPages((page) => page.out)

    // component@version -> module -> { index, pages: [{ page, ids }] }
    const modules = new Map()
    for (const page of pages) {
      const { component, version, module: mod, relative } = page.src
      const key = `${component}@${version}`
      if (!modules.has(key)) modules.set(key, new Map())
      const byModule = modules.get(key)
      if (!byModule.has(mod)) byModule.set(mod, { index: null, pages: [] })
      const entry = byModule.get(mod)
      const ids = new Set()
      for (const m of page.contents.toString().matchAll(/\bid="([^"]+)"/g)) ids.add(m[1])
      const title = (page.asciidoc && page.asciidoc.doctitle) || ''
      entry.pages.push({ page, ids, titleId: toId(title.replace(/<[^>]+>/g, '')), stemId: toId(page.src.stem) })
      if (relative === 'index.adoc') entry.index = page
    }

    const resolveVersion = (componentName, legacyVersion) => {
      const component = contentCatalog.getComponent(componentName)
      if (!component) return undefined
      if (legacyVersion === 'latest') return component.latest.version
      // Legacy URLs name a release as Release-1.0.4 or as bare 1.0.4 (see caddy/Caddyfile).
      for (const name of [legacyVersion, `Release-${legacyVersion}`]) {
        if (component.versions.some((v) => v.version === name)) return name
      }
      return component.latest.version
    }

    const stats = { anchorMissing: 0, anchorAmbiguous: 0, otherVersion: 0 }

    // Module entry for the resolved version; when that version lacks the module (EL, BEL
    // and AQL_examples exist only on development), the newest other version that has it.
    const findModule = (componentName, version, mod) => {
      const entry = modules.get(`${componentName}@${version}`)?.get(mod)
      if (entry) return entry
      const component = contentCatalog.getComponent(componentName)
      for (const v of component.versions) {
        const other = modules.get(`${componentName}@${v.version}`)?.get(mod)
        if (other) {
          stats.otherVersion++
          return other
        }
      }
      return undefined
    }

    const findTarget = (componentName, legacyVersion, doc, fragment) => {
      const version = resolveVersion(componentName, legacyVersion)
      if (version === undefined) return undefined
      const entry = findModule(componentName, version, doc === '' || doc === 'index' ? 'ROOT' : doc)
      if (!entry) return undefined
      const index = entry.index || entry.pages[0].page
      const id = fragment ? safeDecode(fragment.slice(1)) : undefined
      if (id) {
        const hits = entry.pages.filter((p) => p.ids.has(id))
        if (hits.length > 1) stats.anchorAmbiguous++
        // Several chapter pages can share a generic id (_overview); prefer the index page.
        const hit = hits.find((p) => p.page === index) || hits[0]
        if (hit) return { page: hit.page, fragment }
        // A legacy chapter heading (#_time_types) is a page title here, which has no id:
        // match the page whose title or file name gives that id.
        const chapter = entry.pages.find((p) => p.titleId === id || p.stemId === id)
        if (chapter) return { page: chapter.page, fragment: '' }
        stats.anchorMissing++
      }
      // Anchor not found on any page of the module: land on the module index.
      return { page: index, fragment: '' }
    }

    const relativeUrl = (from, to) => {
      const fromDir = from.endsWith('/') ? from : path.posix.dirname(from) + '/'
      let rel = path.posix.relative(fromDir, to)
      if (to.endsWith('/') && rel !== '') rel += '/'
      return rel === '' ? './' : rel
    }

    let rewritten = 0
    const unmapped = new Map()
    for (const page of pages) {
      const html = page.contents.toString()
      if (!html.includes('specifications.openehr.org/releases/')) continue
      const out = html.replace(LEGACY_LINK, (tag, before, component, version, doc, fragment = '', after) => {
        const target = findTarget(component, version, doc, fragment)
        if (!target || !target.page) {
          const key = `${component}/${version}/${doc}`
          unmapped.set(key, (unmapped.get(key) || 0) + 1)
          return tag
        }
        rewritten++
        const href = relativeUrl(page.pub.url, target.page.pub.url) + target.fragment
        // Internal link now: drop the new-window attributes the ^ shorthand added.
        const attrs = `${before} ${after}`
          .replace(/\btarget="_blank"/, '')
          .replace(/\brel="noopener"/, '')
          .replace(/\s+/g, ' ')
          .trim()
        return `<a href="${href}"${attrs ? ' ' + attrs : ''}>`
      })
      if (out !== html) page.contents = Buffer.from(out)
    }

    const unmappedTotal = [...unmapped.values()].reduce((a, b) => a + b, 0)
    logger.info(`Rewrote ${rewritten} legacy specification links; ${unmappedTotal} left (no matching component or module)`)
    logger.info(
      `  anchor not found, linked module index: ${stats.anchorMissing}; anchor on several pages: ${stats.anchorAmbiguous}; module only in another version: ${stats.otherVersion}`
    )
    const top = [...unmapped.entries()].sort((a, b) => b[1] - a[1]).slice(0, 15)
    for (const [key, count] of top) logger.info(`  left: ${count} x releases/${key}`)
  })
}
