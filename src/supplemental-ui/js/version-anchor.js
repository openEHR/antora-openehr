// Version switcher (explore panel, bottom left): keep the position on the page.
// helpers/versionLink.js links to the same page in the other version; the link has no #fragment,
// so the reader lands at the top. On click, carry the current #fragment over when the link
// targets the same page, i.e. its path differs from the current one in one segment (the version).
;(function () {
  'use strict'
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('.nav-panel-explore .versions a')
    if (!a || !window.location.hash || a.hash) return
    var here = window.location.pathname.split('/')
    var there = a.pathname.split('/')
    if (here.length !== there.length) return
    var diff = 0
    for (var i = 0; i < here.length; i++) if (here[i] !== there[i]) diff++
    if (diff === 1) a.hash = window.location.hash
  })
})()
