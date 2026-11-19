import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  enter(event) {
    if (event.pointerType === "mouse" && !this.element.open) {
      this.element.open = true
      this.openedByHover = true
    }
  }

  pin(event) {
    if (event.detail === 0 || !this.openedByHover || !this.element.open) return

    event.preventDefault()
    this.openedByHover = false
  }

  leave(event) {
    if (event.pointerType === "mouse" && this.openedByHover && !this.element.contains(document.activeElement)) {
      this.element.open = false
      this.openedByHover = false
    }
  }
}
