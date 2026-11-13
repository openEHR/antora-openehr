'use strict'

// URL for a version in the explore panel (bottom left).
// For the component being read: the current page in that version, or the version's start page when
// the page does not exist there (page.versions marks it as missing). For other components: the start page.
module.exports = (component, componentVersion, { data: { root } }) => {
  const page = root.page
  if (!page || !page.component || page.component.name !== component.name) return componentVersion.url
  const match = (page.versions || []).find((it) => it.version === componentVersion.version)
  return match ? match.url : componentVersion.url
}
