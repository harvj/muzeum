import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tooltip"]

  connect() {
    this.resize = new ResizeObserver(() => {
      this.hide()
      for (const name of this.element.querySelectorAll("[data-overflow-name]")) {
        const focusable = !this.mobile() && this.clipped(name) && !name.querySelector("a")
        if (focusable) name.tabIndex = 0
        else name.removeAttribute("tabindex")
      }
    })
    this.resize.observe(this.element)
  }

  disconnect() {
    this.resize.disconnect()
  }

  preview(event) {
    const name = event.target.closest("[data-overflow-name]")
    if (!name || !this.clipped(name) || this.mobile()) return

    const tooltip = this.tooltipTarget
    const bounds = name.getBoundingClientRect()
    tooltip.textContent = name.textContent.trim()
    tooltip.showPopover()
    const left = Math.max(8, Math.min(bounds.left, innerWidth - tooltip.offsetWidth - 8))
    const top = bounds.bottom + tooltip.offsetHeight <= innerHeight ? bounds.bottom : bounds.top - tooltip.offsetHeight
    tooltip.style.left = `${left}px`
    tooltip.style.top = `${Math.max(0, top)}px`
    this.previewed = name
  }

  leave(event) {
    const next = event.relatedTarget
    if (this.previewed && next && (this.previewed.contains(next) || this.tooltipTarget.contains(next))) return

    this.hide()
  }

  hide() {
    if (this.hasTooltipTarget && this.tooltipTarget.matches(":popover-open")) this.tooltipTarget.hidePopover()
    this.previewed = null
  }

  clipped(name) {
    const text = name.querySelector(":scope > a:only-child") || name
    return text.scrollWidth > text.clientWidth
  }

  mobile() {
    return matchMedia("(max-width: 700px)").matches
  }

  toggle(event) {
    const expanded = this.element.classList.toggle("full-play-names")
    event.currentTarget.setAttribute("aria-pressed", expanded)
  }
}
