(() => {
  "use strict";
  const $ = id => document.getElementById(id);
  const staff = [
    { role: "सुपर एडमिन", name: "शैलेन्दर" },
    { role: "एडमिन", name: "एडमिन कर्मचारी" },
    { role: "मैनेजर", name: "मैनेजर कर्मचारी" },
    { role: "मास्टर", name: "मास्टर कर्मचारी" },
    { role: "लाइनमैन", name: "जावेद" },
    { role: "प्रिंटर", name: "प्रिंटर कर्मचारी" },
    { role: "स्टिकर", name: "स्टिकर कर्मचारी" }
  ];
  const groups = [
    "खरीद समूह","कटिंग समूह","प्रिंटर समूह","स्टिकर समूह","मेटल आईडी समूह",
    "सिलाई विभाग समूह","ओवरलॉक समूह","फोल्डिंग समूह","काज बटन समूह",
    "धागा कटाई समूह","गुणवत्ता जाँच समूह","प्रेस समूह","पैकिंग समूह"
  ];
  let lane = "group";
  let privatePerson = null;
  let activeGroup = "सिलाई विभाग समूह";
  const open = id => $(id).classList.add("on");
  const close = id => $(id).classList.remove("on");
  const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));

  function setLane(next, person = null) {
    lane = next;
    privatePerson = person;
    document.querySelectorAll("[data-lane]").forEach(button => button.classList.toggle("on", button.dataset.lane === lane));
    if (lane === "group") {
      $("chatTitle").textContent = activeGroup;
      $("chatSub").textContent = "इस विभाग के कारीगर · सुपर एडमिन · एडमिन · मैनेजर · मास्टर · लाइनमैन";
    } else {
      $("chatTitle").textContent = person ? person.name : "निजी काम की बात";
      $("chatSub").textContent = person ? `${person.role} · केवल काम की बात` : "☰ से व्यक्ति चुनें";
    }
  }

  function renderStaff() {
    $("staffList").innerHTML = staff.map((person, index) => `${index === 0 || staff[index - 1].role !== person.role ? `<div class="role">${esc(person.role)}</div>` : ""}<button class="person" data-person="${index}"><span class="face">${esc(person.name.slice(0, 1))}</span><div><b>${esc(person.name)}</b><small>${esc(person.role)} · निजी काम की बात</small></div>›</button>`).join("");
    $("receiver").innerHTML = '<option value="">चुनें…</option>' + staff.map(person => `<option>${esc(person.name)} · ${esc(person.role)}</option>`).join("");
    document.querySelectorAll("[data-person]").forEach(button => button.onclick = () => {
      setLane("private", staff[Number(button.dataset.person)]);
      close("staffBack");
    });
  }

  function renderGroups() {
    $("groupList").innerHTML = groups.map((name, index) => `<button class="person" data-group-index="${index}"><span class="face">👥</span><div><b>${esc(name)}</b><small>इसी विभाग का काम</small></div>›</button>`).join("");
    document.querySelectorAll("[data-group-index]").forEach(button => button.onclick = () => {
      activeGroup = groups[Number(button.dataset.groupIndex)];
      setLane("group");
      $("cardSearch").value = "";
      filterCards();
      close("groupBack");
    });
  }

  function filterCards() {
    const q = $("cardSearch").value.trim().toLowerCase();
    document.querySelectorAll("#msgs .card").forEach(card => {
      card.style.display = !q || card.textContent.toLowerCase().includes(q) ? "" : "none";
    });
  }

  function addMessage(title, body, meta = "सिर्फ जाँच · ✓ भेजा") {
    const node = document.createElement("div");
    node.className = "msg me";
    node.innerHTML = `<small>${lane === "group" ? "काम समूह" : esc(privatePerson?.name || "निजी बात")}</small><b>${esc(title)}</b><div>${esc(body)}</div><time>${esc(meta)}</time>`;
    $("msgs").appendChild(node);
    node.scrollIntoView({block:"end"});
  }

  document.querySelectorAll("[data-lane]").forEach(button => button.onclick = () => {
    if (button.dataset.lane === "private") open("staffBack"); else setLane("group");
  });
  $("staffMenu").onclick = () => open("staffBack");
  $("groupMenu").onclick = () => open("groupBack");
  $("cardSearch").oninput = filterCards;
  document.querySelectorAll("[data-close]").forEach(button => button.onclick = () => close(button.dataset.close));
  document.querySelectorAll(".cover").forEach(back => back.onclick = event => { if (event.target === back) close(back.id); });
  $("newBusiness").onclick = () => open("businessBack");
  $("message").onclick = () => open("businessBack");
  $("attach").onclick = () => open("mediaBack");
  $("voice").onclick = () => addMessage("आवाज़ नहीं भेजी गई", "आवाज़ केवल किसी काम के जवाब में भेजी जा सकती है।");

  $("businessForm").onsubmit = event => {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    addMessage(`${data.get("category")} · ${data.get("reference")}`, `जिसे भेजा: ${data.get("receiver")} · ${data.get("remarks")}`);
    event.currentTarget.reset();
    renderStaff();
    close("businessBack");
  };

  document.querySelectorAll("[data-react]").forEach(button => button.onclick = () => {
    const action = button.dataset.react;
    const card = button.closest("[data-card]");
    if (action === "view") {
      addMessage("काम खोला गया", card.querySelector("h2").textContent);
      return;
    }
    if (["reject", "return", "remark", "correction"].includes(action)) {
      const names = {reject:"नामंज़ूर करने का कारण",return:"वापस करने का कारण",remark:"अपनी बात लिखें",correction:"सुधार का कारण"};
      $("reactionTitle").textContent = names[action];
      const form = $("reactionForm");
      form.elements.action.value = action;
      form.elements.card.value = card.dataset.card;
      form.elements.remarks.value = "";
      open("remarkBack");
      return;
    }
    const done = {approve:"मंज़ूर",accept:"काम स्वीकार",receive:"माल मिला"}[action] || "उत्तर दर्ज";
    card.querySelector(".state").textContent = `✅ ${done} · इसी कार्ड में दर्ज · सिर्फ जाँच`;
    card.querySelectorAll("[data-react]").forEach(item => item.disabled = true);
  });

  $("reactionForm").onsubmit = event => {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    const card = document.querySelector(`[data-card="${data.get("card")}"]`);
    card.querySelector(".state").textContent = `✅ उत्तर दर्ज · कारण: ${data.get("remarks")} · सिर्फ जाँच`;
    card.querySelectorAll("[data-react]").forEach(item => item.disabled = true);
    close("remarkBack");
  };

  document.querySelectorAll("[data-media]").forEach(button => button.onclick = () => {
    addMessage("तस्वीर जोड़ी गई", button.dataset.media);
    close("mediaBack");
  });

  renderStaff();
  renderGroups();
  setLane("group");
  window.__TEST70_CONTROLLED_CHAT__ = {mode:"AUTOMATED_TEST",databaseWrites:false,freeChat:false,deviceGallery:false,lanes:["STAFF_GROUP","PRIVATE_BUSINESS"],ready:true};
})();
