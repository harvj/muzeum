import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    let value = "system"
    try { value = localStorage.getItem("muzeum-appearance") || "system" } catch (_) {}
    if (!["system", "light", "dark"].includes(value)) value = "system"
    this.element.querySelector("select").value = value
    this.apply(value)
    this.visibility = () => document.documentElement.dataset.still = String(document.hidden || this.paused)
    document.addEventListener("visibilitychange", this.visibility)
  }
  disconnect() { document.removeEventListener("visibilitychange", this.visibility) }
  change(event) {
    this.apply(event.target.value)
    try {
      if (event.target.value === "system") localStorage.removeItem("muzeum-appearance")
      else localStorage.setItem("muzeum-appearance", event.target.value)
    } catch (_) {}
  }
  apply(value) { document.documentElement.dataset.appearancePreference = value }
  dismiss(event) {
    if (!this.element.open) return
    event.preventDefault()
    this.element.open = false
    this.element.querySelector("summary").focus()
  }
  toggleMotion(event) {
    this.paused = !this.paused
    document.documentElement.dataset.still = String(this.paused)
    event.currentTarget.setAttribute("aria-pressed", String(this.paused))
    event.currentTarget.textContent = this.paused ? "Resume light" : "Pause light"
  }
}
