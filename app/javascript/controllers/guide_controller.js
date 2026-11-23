import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drawer"]

  connect() { this.openFromLocation() }

  openFromLocation() {
    if (!location.hash.startsWith("#guide-")) return
    const section = document.getElementById(location.hash.slice(1))
    if (!this.drawerTarget.contains(section)) return

    if (!this.drawerTarget.open) {
      this.opener ||= document.activeElement
      this.drawerTarget.showModal()
    }
    section.focus()
    section.scrollIntoView({ block: "start" })
  }

  open(event) {
    event.preventDefault()
    this.opener = event.currentTarget
    this.previousHash = location.hash
    history.replaceState(history.state, "", event.currentTarget.hash)
    this.openFromLocation()
  }

  navigate(event) {
    event.preventDefault()
    history.replaceState(history.state, "", event.currentTarget.hash)
    this.openFromLocation()
  }

  dismissOutside(event) {
    if (event.target !== this.drawerTarget) return

    const { left, right, top, bottom } = this.drawerTarget.getBoundingClientRect()
    if (event.clientX < left || event.clientX >= right || event.clientY < top || event.clientY >= bottom) {
      this.close()
    }
  }

  close() { this.drawerTarget.close() }

  closed() {
    this.drawerTarget.querySelectorAll("form").forEach(form => form.reset())
    if (location.hash.startsWith("#guide-")) {
      history.replaceState(history.state, "", this.previousHash || location.pathname + location.search)
    }
    this.previousHash = null
    this.opener?.focus({ preventScroll: true })
    this.opener = null
  }
}
