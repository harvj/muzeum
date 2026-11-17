import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    let value = "system"
    try { value = localStorage.getItem("muzeum-appearance") || "system" } catch (_) {}
    this.element.querySelector("select").value = value
    this.apply(value)
    this.visibility = () => document.documentElement.dataset.still = String(document.hidden || this.paused)
    document.addEventListener("visibilitychange", this.visibility)
  }
  disconnect() { document.removeEventListener("visibilitychange", this.visibility) }
  change(event) {
    this.apply(event.target.value)
    try { localStorage.setItem("muzeum-appearance", event.target.value) } catch (_) {}
  }
  apply(value) { document.documentElement.dataset.appearance = value }
  toggleMotion(event) {
    this.paused = !this.paused
    document.documentElement.dataset.still = String(this.paused)
    event.currentTarget.setAttribute("aria-pressed", String(this.paused))
    event.currentTarget.textContent = this.paused ? "Resume light" : "Pause light"
  }
}
