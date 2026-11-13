'use strict'

// Splits the Lunr search index by version, so that search finds only the version the reader is on.
//
//   search-index.js                         latest: the latest release of each component
//                                           (components without a release are left out)
//   search-index-development.js             development: the development version of each component
//   search-index-<COMPONENT>-<VERSION>.js   one older release of one component
//
// The partial src/supplemental-ui/partials/search-scripts.hbs loads the file for the current page.
// Register after @antora/lunr-extension, which keeps building the UI assets and the default index.

const { generateIndex } = require('@antora/lunr-extension')

const DEVELOPMENT = 'development'

function register ({ config = {} }) {
  const logger = this.getLogger('scoped-search-index')
  const { indexByHeading = true, languages, extraStopWords } = config

  this.on('beforePublish', ({ playbook, siteCatalog, contentCatalog }) => {
    const scopes = new Map() // file basename -> predicate on page.src
    scopes.set('search-index', (src) => {
      const latest = contentCatalog.getComponent(src.component).latest
      return latest.version !== DEVELOPMENT && src.version === latest.version
    })
    scopes.set(`search-index-${DEVELOPMENT}`, (src) => src.version === DEVELOPMENT)
    for (const component of contentCatalog.getComponents()) {
      for (const { version } of component.versions) {
        if (version === DEVELOPMENT || version === component.latest.version) continue
        scopes.set(scopedIndexName(component.name, version), (src) =>
          src.component === component.name && src.version === version)
      }
    }

    const existing = siteCatalog.getFiles().find((file) => file.out?.path === 'search-index.js')
    for (const [name, inScope] of scopes) {
      const scopedCatalog = {
        getPages: (filter) => contentCatalog.getPages((page) => inScope(page.src) && filter(page)),
        getComponents: () => contentCatalog.getComponents(),
      }
      const index = generateIndex(playbook, scopedCatalog, {
        indexLatestOnly: false,
        indexByHeading,
        languages,
        extraStopWords,
        logger: { info: () => undefined },
      })
      if (!index.index) continue
      const file = generateIndex.createIndexFile(index)
      file.out.path = `${name}.js`
      file.pub.url = `/${name}.js`
      file.src.stem = name
      if (name === 'search-index' && existing) {
        existing.contents = file.contents
      } else {
        siteCatalog.addFile(file)
      }
      logger.info(`${name}.js: ${Object.keys(index.store.documents || index.store).length} entries`)
    }
  })
}

function scopedIndexName (component, version) {
  return `search-index-${component}-${version}`.replace(/[^A-Za-z0-9._-]/g, '_')
}

module.exports = { register, scopedIndexName }
