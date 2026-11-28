import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["color", "rationale", "status"]
  static values = { colors: Array }

  connect() { this.restore() }

  choose(event) {
    const input = event.target
    if (input.checked && this.selected.length === 3) {
      input.checked = false
      this.statusTarget.textContent = "Remove a color before selecting another."
      return
    }

    this.selected = this.selected.filter(color => color !== input.value)
    if (input.checked) this.selected.push(input.value)
    this.update()
  }

  restore() {
    this.selected = [...this.colorsValue]
    this.update()
  }

  serialize(event) {
    const key = "musical_identity[colors][]"
    event.formData.delete(key)
    this.selected.forEach(color => event.formData.append(key, color))
  }

  update() {
    this.colorTargets.forEach(input => {
      const index = this.selected.indexOf(input.value)
      input.parentElement.querySelector(".identity-choice-order").textContent = index < 0 ? "" : index + 1
    })
    const exceptional = this.selected.length === 3
    this.rationaleTarget.required = exceptional
    this.statusTarget.textContent = exceptional ? "Three colors selected. Add a musical rationale." : ""
  }
}
