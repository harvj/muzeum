import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["choice", "proposal", "warning"]

  connect() { this.restoreSelection() }

  restoreSelection() {
    const url = new URL(window.location.href)
    const edition = url.searchParams.get("edition")
    if (this.hasWarningTarget && !url.searchParams.has("review_edition")) {
      url.searchParams.set("review_edition", "1")
      history.replaceState(history.state, "", url)
    }
    if (edition) {
      this.choiceTargets.forEach(choice => { choice.checked = !url.searchParams.has("review_edition") && (choice.value === edition || choice.dataset.sourceEditions?.split(",").includes(edition)) })
    }
    this.showSelection()
  }

  choose() {
    const edition = this.choiceTargets.find(choice => choice.checked)?.value
    if (!edition) return

    const url = new URL(window.location.href)
    url.searchParams.set("edition", edition)
    url.searchParams.delete("review_edition")
    history.replaceState(history.state, "", url)
    if (this.hasWarningTarget) this.warningTarget.hidden = true
    this.showSelection()
  }

  showSelection() {
    const edition = this.choiceTargets.find(choice => choice.checked)?.value
    this.proposalTargets.forEach(proposal => {
      proposal.hidden = proposal.dataset.edition !== edition
    })
  }
}
