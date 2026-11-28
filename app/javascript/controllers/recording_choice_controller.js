import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  preview() {
    this.element.requestSubmit()
  }
}
