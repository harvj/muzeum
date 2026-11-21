import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "username", "applications", "links"]
  static values = { url: String, binding: String }

  connect() {
    this.refresh()
  }

  disconnect() {
    this.clear()
  }

  restore(event) {
    if (event.persisted) this.refresh()
  }

  toggle() {
    if (this.element.open) this.refresh()
  }

  escape(event) {
    if (!this.element.open) return
    event.preventDefault()
    this.element.open = false
    this.triggerTarget.focus()
  }

  outside(event) {
    if (!this.element.open || this.element.contains(event.target)) return
    const restoreFocus = this.element.contains(document.activeElement)
    this.element.open = false
    if (restoreFocus) this.triggerTarget.focus()
  }

  clear() {
    this.request?.abort()
    this.request = null
    clearTimeout(this.expiration)
    this.hideApplications()
    this.usernameTarget.textContent = "Signed in"
  }

  hideApplications() {
    if (this.applicationsTarget.contains(document.activeElement)) this.triggerTarget.focus()
    this.applicationsTarget.hidden = true
    this.linksTarget.replaceChildren()
  }

  async refresh() {
    this.clear()
    if (document.hidden) return
    const request = new AbortController()
    this.request = request
    const startedAt = performance.now()
    const timeout = setTimeout(() => request.abort(), 10000)
    try {
      const response = await fetch(this.urlValue, {
        cache: "no-store", credentials: "same-origin", signal: request.signal,
        headers: { "X-Muzeum-Shell-Session": this.bindingValue }
      })
      if (!response.ok) return
      const evidence = await response.json()
      if (this.request !== request || request.signal.aborted) return
      const remaining = evidence.valid_for * 1000 - (performance.now() - startedAt) - 1000
      if (!(remaining > 0 && remaining <= 60000)) return
      this.usernameTarget.textContent = evidence.username
      const links = evidence.applications.map(({ name, canonical_url }) => {
        const link = document.createElement("a")
        link.textContent = name
        link.href = canonical_url
        return link
      })
      this.linksTarget.replaceChildren(...links)
      this.applicationsTarget.hidden = links.length === 0
      this.expiration = setTimeout(() => this.refresh(), remaining)
    } catch {
      // Every fetch starts with an empty menu, so errors cannot retain eligibility.
    } finally {
      clearTimeout(timeout)
    }
  }
}
