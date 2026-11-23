import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.regions = document.querySelectorAll("body > main, body > footer")
    this.observer = new ResizeObserver(() => this.schedule())
    this.observer.observe(this.element)
    this.regions.forEach(region => this.observer.observe(region))
    this.schedule()
  }

  disconnect() {
    this.observer.disconnect()
    cancelAnimationFrame(this.frame)
    this.frame = undefined
    document.documentElement.style.removeProperty("--shell-header-height")
    this.regions.forEach(region => {
      region.removeAttribute("data-shell-fading")
      region.style.removeProperty("--shell-cover")
    })
  }

  schedule() {
    if (this.frame !== undefined) return

    this.frame = requestAnimationFrame(() => {
      this.frame = undefined
      const boundary = this.element.getBoundingClientRect().bottom
      document.documentElement.style.setProperty("--shell-header-height", `${this.element.offsetHeight}px`)
      this.regions.forEach(region => {
        const cover = boundary - region.getBoundingClientRect().top
        const active = window.scrollY > 0 && cover > -24
        region.toggleAttribute("data-shell-fading", active)
        if (active) region.style.setProperty("--shell-cover", `${cover}px`)
      })
    })
  }

  clearFocus({ target }) {
    if (target.matches(":focus-visible") && target.closest("main, footer") &&
        target.getBoundingClientRect().top < this.element.getBoundingClientRect().bottom) {
      target.scrollIntoView({ block: "center", behavior: "instant" })
    }
  }
}
