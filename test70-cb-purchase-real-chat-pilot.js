(() => {
  "use strict";
  const $ = id => document.getElementById(id);
  const staff = [
    { role: "SUPER ADMIN", name: "Shailender" },
    { role: "ADMIN", name: "Admin Staff" },
    { role: "MANAGER", name: "Manager Staff" },
    { role: "MASTER", name: "Master Staff" },
    { role: "LINEMAN", name: "Javed" },
    { role: "PRINTER", name: "Printer Staff" },
    { role: "STICKER", name: "Sticker Staff" }
  ];
  let lane = "group";
  let privatePerson = null;
  const open = id => $(id).classList.add("on");
  const close = id => $(id).classList.remove("on");
  const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));

  function setLane(next, person = null) {
    lane = next;
    privatePerson = person;
    document.querySelectorAll("[data-lane]").forEach(button => button.classList.toggle("on", button.dataset.lane === lane));
    if (lane === "group") {
      $("chatTitle").textContent = "REDZED · OPERATIONS GROUP";
      $("chatSub").textContent = "Super Admin · Admin · Manager · Master · Lineman · Printer · Sticker";
    } else {
      $("chatTitle").textContent = person ? person.name : "PRIVATE BUSINESS CHAT";
      $("chatSub").textContent = person ? `${person.role} · Business messages only` : "STAFF ☰ से व्यक्ति चुनें";
    }
  }

  function renderStaff() {
    $("staffList").innerHTML = staff.map((person, index) => `${index === 0 || staff[index - 1].role !== person.role ? `<div class="role">${esc(person.role)}</div>` : ""}<button class="person" data-person="${index}"><span>${esc(person.name.slice(0, 1))}</span><div><b>${esc(person.name)}</b><small>${esc(person.role)} · Private business chat</small></div>›</button>`).join("");
    $("receiver").innerHTML = '<option value="">Select…</option>' + staff.map(person => `<option>${esc(person.name)} · ${esc(person.role)}</option>`).join("");
    document.querySelectorAll("[data-person]").forEach(button => button.onclick = () => {
      setLane("private", staff[Number(button.dataset.person)]);
      close("staffBack");
    });
  }

  function addMessage(title, body, meta = "TEST PREVIEW · ✓ SENT LOCALLY · NO DATABASE WRITE") {
    const node = document.createElement("div");
    node.className = "msg me";
    node.innerHTML = `<small>${lane === "group" ? "OPERATIONS GROUP" : esc(privatePerson?.name || "PRIVATE")}</small><b>${esc(title)}</b><div>${esc(body)}</div><time>${esc(meta)}</time>`;
    $("msgs").appendChild(node);
    node.scrollIntoView({block:"end"});
  }

  document.querySelectorAll("[data-lane]").forEach(button => button.onclick = () => {
    if (button.dataset.lane === "private") open("staffBack"); else setLane("group");
  });
  $("staffMenu").onclick = () => open("staffBack");
  document.querySelectorAll("[data-close]").forEach(button => button.onclick = () => close(button.dataset.close));
  document.querySelectorAll(".backdrop").forEach(back => back.onclick = event => { if (event.target === back) close(back.id); });
  $("newBusiness").onclick = () => open("businessBack");
  $("message").onclick = () => open("businessBack");
  $("attach").onclick = () => open("mediaBack");
  $("voice").onclick = () => addMessage("VOICE BLOCKED", "Voice केवल किसी workflow card के Reply action से भेजी जा सकती है।");

  $("businessForm").onsubmit = event => {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    addMessage(`${data.get("category")} · ${data.get("reference")}`, `Addressed To: ${data.get("receiver")} · ${data.get("remarks")}`);
    event.currentTarget.reset();
    renderStaff();
    close("businessBack");
  };

  document.querySelectorAll("[data-react]").forEach(button => button.onclick = () => {
    const action = button.dataset.react;
    const card = button.closest("[data-card]");
    if (["reject", "return", "remark"].includes(action)) {
      $("reactionTitle").textContent = `${action.toUpperCase()} · REMARKS REQUIRED`;
      const form = $("reactionForm");
      form.elements.action.value = action;
      form.elements.card.value = card.dataset.card;
      form.elements.remarks.value = "";
      open("remarkBack");
      return;
    }
    card.querySelector(".status").textContent = `✅ ${action === "approve" ? "APPROVED" : "ACCEPTED"} · action recorded in this card · TEST ONLY`;
    card.querySelectorAll("[data-react]").forEach(item => item.disabled = true);
  });

  $("reactionForm").onsubmit = event => {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    const card = document.querySelector(`[data-card="${data.get("card")}"]`);
    card.querySelector(".status").textContent = `✅ ${String(data.get("action")).toUpperCase()} · Remarks: ${data.get("remarks")} · TEST ONLY`;
    card.querySelectorAll("[data-react]").forEach(item => item.disabled = true);
    close("remarkBack");
  };

  document.querySelectorAll("[data-media]").forEach(button => button.onclick = () => {
    addMessage("INTERNAL MEDIA ATTACHED", button.dataset.media);
    close("mediaBack");
  });

  renderStaff();
  setLane("group");
  window.__TEST70_CONTROLLED_CHAT__ = {mode:"AUTOMATED_TEST",databaseWrites:false,freeChat:false,deviceGallery:false,lanes:["STAFF_GROUP","PRIVATE_BUSINESS"],ready:true};
})();
