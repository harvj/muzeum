import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = { url: String, version: String }

  connect() { if (this.versionValue) this.schedule() }
  disconnect() { clearTimeout(this.timer); this.abort?.abort() }
  schedule() { this.timer = setTimeout(() => this.update(), 10000) }

  async update() {
    if (document.hidden) { this.schedule(); return }
    this.abort = new AbortController()
    try {
      const url = new URL(this.urlValue, location.origin)
      url.searchParams.set("version", this.versionValue)
      const response = await fetch(url, {
        headers: { Accept: "text/vnd.turbo-stream.html" }, credentials: "same-origin", signal: this.abort.signal
      })
      if (response.redirected) { location.assign(response.url); return }
      if (response.ok && response.status !== 204) Turbo.renderStreamMessage(await response.text())
    } catch (error) {
      if (error.name === "AbortError") return
    }
    if (this.element.isConnected) this.schedule()
  }
}
