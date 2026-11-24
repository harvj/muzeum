import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = { checkAt: String }
  connect() {
    this.source = this.element.querySelector("turbo-cable-stream-source")
    this.observer = new MutationObserver(() => this.catchUp())
    this.observer.observe(this.source, { attributes: true, attributeFilter: ["connected"] })
    this.catchUp()
    this.checkAtValueChanged()
  }

  disconnect() {
    this.observer.disconnect()
    clearTimeout(this.checkTimer)
  }

  checkAtValueChanged() {
    clearTimeout(this.checkTimer)
    const delay = Date.parse(this.checkAtValue) - Date.now()
    if (delay > 0) {
      this.checkTimer = setTimeout(() => this.refresh(), delay + 250)
    }
  }

  preserveConnection(event) {
    if (event.target === this.source && event.detail.attributeName === "connected") event.preventDefault()
  }

  catchUp() {
    if (this.source.hasAttribute("connected")) this.refresh()
  }

  refresh() {
    Turbo.session.refresh(document.baseURI, { method: "morph", scroll: "preserve" })
  }
}
