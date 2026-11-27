import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["summary", "primary", "effect"]

  connect() {
    this.update()
  }

  update() {
    const editions = [...this.element.querySelectorAll("[data-review-edition]:checked")]
    const configurations = editions.filter((input) => input.dataset.reviewEdition === "configuration")
    for (const primary of this.primaryTargets) {
      const checked = configurations.some((input) => input.value === primary.value)
      primary.disabled = !checked
      primary.required = checked && configurations.length > 1
      if (!checked) primary.checked = false
    }
    if (this.hasEffectTarget) {
      const primary = configurations.length === 1 ? configurations[0] :
        configurations.find((input) => this.primaryTargets.some((radio) => radio.checked && radio.value === input.value))
      const admissions = editions.filter((input) => input.dataset.reviewEdition === "program")
      if (primary && primary.dataset.reviewExistingAlbum === "false") admissions.push(primary)
      const recordings = new Set(admissions.flatMap((input) => input.dataset.reviewNewRecordings.split(",")).filter(Boolean))
      this.effectTarget.textContent = editions.length ?
        `New releases: ${admissions.length}. Release tracks with no current recording match: ${recordings.size}.` : ""
    }
    if (this.hasSummaryTarget) {
      this.summaryTarget.replaceChildren()
      for (const edition of editions) {
        const item = document.createElement("li")
        item.textContent = edition.dataset.reviewLabel
        this.summaryTarget.append(item)
      }
      if (editions.length === 0) {
        const item = document.createElement("li")
        item.textContent = "No pending release selections."
        this.summaryTarget.append(item)
      }
    }
  }
}
