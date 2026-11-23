'use strict'

// URL for a version in the explore panel (bottom left).
// For the component being read: the current page in that version; if it does not exist there,
// the nearest existing parent page (page attribute version-fallbacks, set by the
// version-fallback extension); otherwise the version's start page.
// For other components: the start page.
module.exports = (component, componentVersion, { data: { root } }) => {
  const page = root.page
  if (!page || !page.component || page.component.name !== component.name) return componentVersion.url
  const match = (page.versions || []).find((it) => it.version === componentVersion.version && !it.missing)
  if (match) return match.url
  const fallbacks = (page.attributes || {})['version-fallbacks']
  if (fallbacks) {
    try {
      const url = JSON.parse(fallbacks)[componentVersion.version]
      if (url) return url
    } catch (e) {}
  }
  return componentVersion.url
}
