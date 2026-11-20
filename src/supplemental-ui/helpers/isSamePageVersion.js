'use strict'

// True when the explore panel link for this version opens the current page in that version,
// so the section anchor (#...) can be carried over by the script in nav-explore.hbs.
module.exports = (component, componentVersion, { data: { root } }) => {
  const page = root.page
  if (!page || !page.component || page.component.name !== component.name) return false
  return (page.versions || []).some((it) => it.version === componentVersion.version && !it.missing)
}
