let Hooks = {}

Hooks.Clipboard = {
    mounted() {
        this.handleEvent("copy-to-clipboard", ({ text: text }) => {
            navigator.clipboard.writeText(text).then(() => {
                this.pushEventTo(this.el, "copied-to-clipboard", { text: text })
                setTimeout(() => {
                    this.pushEventTo(this.el, "reset-copied", {})
                }, 2000)
            })
        })
    }
}

Hooks.ScrollBottom = {
    mounted() {
        this.scrollToBottom()
        this.observer = new MutationObserver(() => this.scrollToBottom())
        this.observer.observe(this.el, { childList: true, subtree: true })
    },
    updated() {
        this.scrollToBottom()
    },
    destroyed() {
        if (this.observer) this.observer.disconnect()
    },
    scrollToBottom() {
        this.el.scrollTop = this.el.scrollHeight
    }
}

Hooks.ChatInput = {
    mounted() {
        this.textarea = this.el.querySelector("textarea")
        if (!this.textarea) return

        this.textarea.addEventListener("input", () => {
            this.resize()
            this.detectMention()
        })

        this.textarea.addEventListener("keydown", (e) => {
            if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault()
                const content = this.textarea.value.trim()
                if (content !== "") {
                    this.pushEvent("send_message", { content: content })
                    this.textarea.value = ""
                    this.resize()
                    this.pushEvent("clear_mention_search", {})
                }
            }
        })

        this.handleEvent("contact_tagged", ({ name }) => {
            const text = this.textarea.value
            const cursorPos = this.textarea.selectionStart
            const beforeCursor = text.substring(0, cursorPos)
            const afterCursor = text.substring(cursorPos)
            const replaced = beforeCursor.replace(/@(\w*)$/, `@${name} `)
            this.textarea.value = replaced + afterCursor
            this.textarea.selectionStart = replaced.length
            this.textarea.selectionEnd = replaced.length
            this.textarea.focus()
            this.resize()
        })
    },
    resize() {
        this.textarea.style.height = "auto"
        this.textarea.style.height = Math.min(this.textarea.scrollHeight, 120) + "px"
    },
    detectMention() {
        const cursorPos = this.textarea.selectionStart
        const textBeforeCursor = this.textarea.value.substring(0, cursorPos)
        const match = textBeforeCursor.match(/@(\w{2,})$/)
        if (match) {
            this.pushEvent("search_contacts_for_mention", { query: match[1] })
        } else {
            this.pushEvent("clear_mention_search", {})
        }
    }
}

export default Hooks