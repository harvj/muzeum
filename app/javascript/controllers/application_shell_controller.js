import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }
  static targets = ["trigger", "username", "applications", "destinations"]

  connect() {
    this.refresh()
  }

  disconnect() {
    this.cancelRefresh()
  }

  restore(event) {
    if (event.persisted) this.refresh()
  }

  toggle(event) {
    if (event.target !== this.element) return
    if (this.element.open) this.refresh()
    else this.apply(this.usernameTarget.textContent, [])
  }

  escape(event) {
    if (!this.element.open) return
    event.preventDefault()
    this.element.open = false
    this.triggerTarget.focus()
  }

  dismiss(event) {
    if (!this.element.open || this.element.contains(event.target)) return
    if (this.element.contains(document.activeElement)) this.triggerTarget.focus()
    this.element.open = false
  }

  cancelRefresh() {
    clearTimeout(this.expiry)
    this.request?.abort()
  }

  clear() {
    this.cancelRefresh()
    this.apply("Signed in", [])
  }

  async refresh() {
    this.clear()
    const request = this.request = new AbortController()
    const timeout = setTimeout(() => request.abort(), 6000)
    try {
      const response = await fetch(this.urlValue, { signal: request.signal, redirect: "error", cache: "no-store" })
      if (response.status === 401 && !request.signal.aborted) {
        window.location.replace("/")
        return
      }
      if (response.status !== 200) return
      const result = await response.json()
      const ttl = Math.min(60000, result.expires_at * 1000 - Date.now())
      if (request.signal.aborted || !(ttl > 0)) return

      this.apply(result.username, this.element.open ? result.destinations : [])
      this.expiry = setTimeout(() => this.clear(), ttl)
    } catch (_) {
      // Unavailable evidence leaves the local session controls available.
    } finally {
      clearTimeout(timeout)
    }
  }

  apply(username, destinations) {
    this.usernameTarget.textContent = username
    this.triggerTarget.setAttribute("aria-label", username)
    if (this.destinationsTarget.contains(document.activeElement)) this.triggerTarget.focus()
    this.destinationsTarget.replaceChildren(...destinations.map(({ name, url }) => {
      const link = document.createElement("a")
      link.href = url
      link.textContent = name
      return link
    }))
    this.applicationsTarget.hidden = destinations.length === 0
  }
}
