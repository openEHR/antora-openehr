'use strict'

// Shows release versions without the "Release-" prefix ("Release-1.2.0" -> "1.2.0").
// The version name and the URL stay "Release-1.2.0"; only the label changes.
// The latest and development badges are added by the nav-explore and page-versions partials.

module.exports.register = function () {
  this.on('contentClassified', ({ contentCatalog }) => {
    for (const component of contentCatalog.getComponents()) {
      for (const componentVersion of component.versions) {
        const match = /^Release-(.+)$/.exec(componentVersion.version)
        if (match && componentVersion.displayVersion === componentVersion.version) {
          componentVersion.displayVersion = match[1]
        }
      }
    }
  })
}
