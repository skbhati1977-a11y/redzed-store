/*
REDZED Smart Caption Builder V1

Usage:
const builder = new RRCaptionBuilder({
  masterType: 'art',
  categoryInput: document.getElementById('designCategory'),
  container: document.getElementById('captionBuilder'),
  outputInput: document.getElementById('description')
});

await builder.load();
const selectedItems = builder.getItems();
await supabaseClient.rpc('rr_save_art_captions', {
  p_art_id: artId,
  p_items: selectedItems
});
*/

class RRCaptionBuilder {
  constructor(options) {
    this.masterType = options.masterType;
    this.categoryInput = options.categoryInput || null;
    this.printTypeInput = options.printTypeInput || null;
    this.container = options.container;
    this.outputInput = options.outputInput || null;
    this.suggestions = [];
    this.selected = [];
    this.groupOrder = [
      "category","collar","neck","shoulder","placket","sleeve","cuff",
      "hood","pocket","waist","bottom","fit","fabric","trim",
      "construction","finish","process","base","flash","stroke",
      "cure","pressure","press","peel","registration","other"
    ];

    if (!this.container) {
      throw new Error("Caption builder container is required.");
    }

    this.categoryInput?.addEventListener("change", () => this.load());
    this.printTypeInput?.addEventListener("change", () => this.load());
  }

  key() {
    const categoryKey = this.categoryInput?.value?.trim().toLowerCase() || "";
    const printTypeKey = this.printTypeInput?.value?.trim().toLowerCase() || "";
    return { categoryKey, printTypeKey };
  }

  async load(existingItems = null) {
    const { categoryKey, printTypeKey } = this.key();

    let query = supabaseClient
      .from("rr_caption_library")
      .select("*")
      .eq("master_type", this.masterType)
      .eq("is_active", true)
      .order("is_default", { ascending: false })
      .order("use_count", { ascending: false })
      .order("sort_order", { ascending: true });

    if (this.masterType === "art" && categoryKey) {
      query = query.or(`category_key.eq.${categoryKey},category_key.is.null`);
    }

    if (this.masterType === "print" && printTypeKey) {
      query = query.or(`print_type_key.eq.${printTypeKey},print_type_key.is.null`);
    }

    const { data, error } = await query;
    if (error) throw error;

    this.suggestions = data || [];

    if (Array.isArray(existingItems)) {
      this.selected = existingItems.map((item) => ({
        id: item.id || null,
        group: item.group || "other",
        text: item.text || ""
      })).filter((item) => item.text);
    } else {
      this.selected = this.suggestions
        .filter((item) => item.is_default)
        .map((item) => ({
          id: item.id,
          group: item.group_code,
          text: item.caption_text
        }));
    }

    this.render();
    this.syncOutput();
  }

  selectedKey(item) {
    return `${item.group}::${item.text}`.toLowerCase();
  }

  isSelected(suggestion) {
    const key = `${suggestion.group_code}::${suggestion.caption_text}`.toLowerCase();
    return this.selected.some((item) => this.selectedKey(item) === key);
  }

  toggle(suggestion) {
    const key = `${suggestion.group_code}::${suggestion.caption_text}`.toLowerCase();
    const index = this.selected.findIndex((item) => this.selectedKey(item) === key);

    if (index >= 0) {
      this.selected.splice(index, 1);
    } else {
      this.selected.push({
        id: suggestion.id,
        group: suggestion.group_code,
        text: suggestion.caption_text
      });
    }

    this.render();
    this.syncOutput();
  }

  async addCustom(text, group = "other", saveReusable = true) {
    const clean = String(text || "").trim();
    if (!clean) return;

    let item = { id: null, group, text: clean };

    if (saveReusable) {
      const { categoryKey, printTypeKey } = this.key();
      const { data, error } = await supabaseClient.rpc(
        "rr_add_caption_suggestion",
        {
          p_master_type: this.masterType,
          p_group_code: group,
          p_caption_text: clean,
          p_category_key: this.masterType === "art" ? categoryKey || null : null,
          p_print_type_key: this.masterType === "print" ? printTypeKey || null : null,
          p_make_default: false
        }
      );

      if (error) throw error;
      item = {
        id: data.id,
        group: data.group_code,
        text: data.caption_text
      };
      this.suggestions.push(data);
    }

    if (!this.selected.some((x) => this.selectedKey(x) === this.selectedKey(item))) {
      this.selected.push(item);
    }

    this.render();
    this.syncOutput();
  }

  removeSelected(index) {
    this.selected.splice(index, 1);
    this.render();
    this.syncOutput();
  }

  syncOutput() {
    const text = this.selected.map((item) => item.text).join(" • ");
    if (this.outputInput) {
      this.outputInput.value = text;
      this.outputInput.dispatchEvent(new Event("input", { bubbles: true }));
    }

    const preview = this.container.querySelector("[data-caption-preview]");
    if (preview) preview.textContent = text || "No caption selected.";
  }

  getItems() {
    return this.selected.map((item) => ({
      id: item.id,
      group: item.group,
      text: item.text
    }));
  }

  render() {
    const grouped = new Map();

    for (const suggestion of this.suggestions) {
      const group = suggestion.group_code || "other";
      if (!grouped.has(group)) grouped.set(group, []);
      grouped.get(group).push(suggestion);
    }

    const sortedGroups = [...grouped.keys()].sort((a,b) => {
      const ai = this.groupOrder.indexOf(a);
      const bi = this.groupOrder.indexOf(b);
      return (ai < 0 ? 999 : ai) - (bi < 0 ? 999 : bi);
    });

    this.container.innerHTML = `
      <div class="rr-caption-selected">
        <div class="rr-caption-title">
          <div>
            <h3>Smart Caption Builder</h3>
            <p>Tick suggestions or add a new fashion term once. It will be reusable next time.</p>
          </div>
        </div>

        <div class="rr-caption-chosen">
          ${this.selected.length
            ? this.selected.map((item,index) => `
              <button type="button" class="rr-caption-pill selected"
                      data-remove-index="${index}">
                ${this.escape(item.text)} ×
              </button>`).join("")
            : `<span class="rr-caption-empty">No caption selected.</span>`}
        </div>

        <div class="rr-caption-preview">
          <small>READY DESCRIPTION</small>
          <strong data-caption-preview></strong>
        </div>
      </div>

      <div class="rr-caption-groups">
        ${sortedGroups.map((group) => `
          <section class="rr-caption-group">
            <h4>${this.escape(this.label(group))}</h4>
            <div class="rr-caption-options">
              ${grouped.get(group).map((suggestion) => `
                <button type="button"
                        class="rr-caption-pill ${this.isSelected(suggestion) ? "selected" : ""}"
                        data-caption-id="${suggestion.id}">
                  ${this.isSelected(suggestion) ? "✓ " : ""}
                  ${this.escape(suggestion.caption_text)}
                </button>`).join("")}
            </div>
          </section>`).join("")}
      </div>

      <div class="rr-caption-add">
        <select data-new-group>
          ${this.groupOrder.map((group) =>
            `<option value="${group}">${this.escape(this.label(group))}</option>`
          ).join("")}
        </select>
        <input data-new-caption type="text"
               placeholder="New fashion detail, e.g. Craft Neck">
        <button type="button" class="rr-caption-add-btn" data-add-caption>
          + Add & Remember
        </button>
      </div>
    `;

    this.container.querySelectorAll("[data-caption-id]").forEach((button) => {
      button.addEventListener("click", () => {
        const suggestion = this.suggestions.find((x) => x.id === button.dataset.captionId);
        if (suggestion) this.toggle(suggestion);
      });
    });

    this.container.querySelectorAll("[data-remove-index]").forEach((button) => {
      button.addEventListener("click", () =>
        this.removeSelected(Number(button.dataset.removeIndex))
      );
    });

    const input = this.container.querySelector("[data-new-caption]");
    const group = this.container.querySelector("[data-new-group]");
    const addButton = this.container.querySelector("[data-add-caption]");

    const add = async () => {
      addButton.disabled = true;
      try {
        await this.addCustom(input.value, group.value, true);
        input.value = "";
      } finally {
        addButton.disabled = false;
      }
    };

    addButton.addEventListener("click", add);
    input.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        add();
      }
    });

    this.syncOutput();
  }

  label(value) {
    return String(value || "")
      .replaceAll("_"," ")
      .replace(/\b\w/g, (char) => char.toUpperCase());
  }

  escape(value) {
    return String(value ?? "").replace(/[&<>"']/g, (char) => ({
      "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"
    })[char]);
  }
}

window.RRCaptionBuilder = RRCaptionBuilder;
