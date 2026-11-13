'use strict'

// Version labels and order in the version menus.
// - Release versions show without the "Release-" prefix ("Release-1.2.0" -> "1.2.0").
//   The version name and the URL stay "Release-1.2.0"; only the label changes.
// - "development" is listed first, then the latest release, then older releases.
//   component.latest is already set when contentClassified fires, so the new order does not change it.
// The latest and development badges are added by the nav-explore and page-versions partials.

const DEVELOPMENT = 'development'

module.exports.register = function () {
  this.on('contentClassified', ({ contentCatalog }) => {
    for (const component of contentCatalog.getComponents()) {
      for (const componentVersion of component.versions) {
        const match = /^Release-(.+)$/.exec(componentVersion.version)
        if (match && componentVersion.displayVersion === componentVersion.version) {
          componentVersion.displayVersion = match[1]
        }
      }
      const i = component.versions.findIndex((it) => it.version === DEVELOPMENT)
      if (i > 0) component.versions.unshift(...component.versions.splice(i, 1))
    }
  })
}
