(function () {
  "use strict";

  var VERSION = "712";
  var gallery = document.getElementById("cbGallery");
  var message = document.getElementById("pmMessage");
  var openButton = document.getElementById("openNewCb");
  var finished = false;

  window.REDZED_PRODUCT_MASTER_LOADER_VERSION = VERSION;

  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function show(title, detail, isError) {
    if (gallery) {
      gallery.setAttribute("aria-busy", isError ? "false" : "true");
      gallery.innerHTML =
        '<article class="pm-empty-card">' +
        (isError ? "" : '<div class="pm-spinner" aria-hidden="true"></div>') +
        "<h3>" + escapeHtml(title) + "</h3>" +
        "<p>" + escapeHtml(detail) + "</p>" +
        "</article>";
    }

    if (message) {
      message.textContent = isError ? "V712 startup error: " + detail : "";
      message.className = isError ? "rr-message error" : "rr-message";
    }

    if (openButton) openButton.disabled = true;
  }

  function fail(detail) {
    if (finished) return;
    finished = true;
    show("Product Master could not start", detail, true);
  }

  function loadScript(src, timeoutMs, done) {
    var script = document.createElement("script");
    var settled = false;
    var timer = window.setTimeout(function () {
      if (settled) return;
      settled = true;
      if (script.parentNode) script.parentNode.removeChild(script);
      done(new Error("Timed out loading " + src));
    }, timeoutMs);

    script.src = src;
    script.async = false;
    script.onload = function () {
      if (settled) return;
      settled = true;
      window.clearTimeout(timer);
      done(null);
    };
    script.onerror = function () {
      if (settled) return;
      settled = true;
      window.clearTimeout(timer);
      done(new Error("Could not load " + src));
    };
    document.body.appendChild(script);
  }

  function loadSupabase(done) {
    if (window.supabase && typeof window.supabase.createClient === "function") {
      done(null);
      return;
    }

    var sources = [
      "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2",
      "https://unpkg.com/@supabase/supabase-js@2"
    ];
    var index = 0;
    var lastError = null;

    function next() {
      if (index >= sources.length) {
        done(lastError || new Error("Supabase library could not load"));
        return;
      }

      var source = sources[index++];
      show("Starting Product Master V712", "Loading database library " + index + "/" + sources.length + "…", false);
      loadScript(source, 12000, function (error) {
        if (!error && window.supabase && typeof window.supabase.createClient === "function") {
          done(null);
          return;
        }
        lastError = error || new Error("Supabase library loaded without createClient");
        next();
      });
    }

    next();
  }

  window.addEventListener("error", function (event) {
    if (finished) return;
    var source = event.filename ? " in " + event.filename.split("/").pop() : "";
    var line = event.lineno ? " at line " + event.lineno : "";
    fail((event.message || "JavaScript error") + source + line);
  });

  window.addEventListener("unhandledrejection", function (event) {
    if (finished) return;
    var reason = event.reason;
    fail(reason && reason.message ? reason.message : String(reason || "Unhandled promise error"));
  });

  show("Starting Product Master V712", "Loader JavaScript is running…", false);

  loadSupabase(function (error) {
    if (error) {
      fail(error.message);
      return;
    }

    show("Starting Product Master V712", "Loading secure configuration…", false);
    loadScript("config.js?v=712", 10000, function (configError) {
      if (configError) {
        fail(configError.message);
        return;
      }

      show("Starting Product Master V712", "Loading REDZED common tools…", false);
      loadScript("real-common.js?v=712", 10000, function (commonError) {
        if (commonError) {
          fail(commonError.message);
          return;
        }

        show("Starting Product Master V712", "Loading Product Master application…", false);
        loadScript("real-product-master-v712-app.js?v=712", 12000, function (appError) {
          if (appError) {
            fail(appError.message);
            return;
          }

          window.setTimeout(function () {
            if (!window.REDZED_PRODUCT_MASTER_BOOTED) {
              fail("Application file loaded, but its startup marker was not set.");
              return;
            }
            finished = true;
          }, 1500);
        });
      });
    });
  });
})();
