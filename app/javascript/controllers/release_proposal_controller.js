import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["choice", "proposal"]

  connect() { this.showSelection() }

  showSelection() {
    this.proposalTargets.forEach(proposal => {
      proposal.hidden = proposal.dataset.edition !== this.choiceTarget.value
    })
  }
}
