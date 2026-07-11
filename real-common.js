
(() => {
  const RR = {};

  RR.safeText = (value) =>
    String(value ?? "").replace(/[&<>"']/g, (char) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#039;"
    })[char]);

  RR.money = (value) => {
    const number = Number(value || 0);
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
      maximumFractionDigits: 2
    }).format(number);
  };

  RR.number = (value, fallback = 0) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  };

  RR.requireOwner = async () => {
    const { data, error } = await supabaseClient.auth.getSession();
    if (error || !data.session) {
      window.location.replace("real-login.html");
      throw new Error("Login required.");
    }

    const user = data.session.user;
    const { data: profile, error: profileError } = await supabaseClient
      .from("rr_user_profiles")
      .select("id, full_name, role_code, is_active")
      .eq("auth_user_id", user.id)
      .single();

    if (
      profileError ||
      !profile?.is_active ||
      !["owner", "admin"].includes(profile.role_code)
    ) {
      await supabaseClient.auth.signOut();
      window.location.replace("real-login.html");
      throw new Error("Owner/Admin access required.");
    }

    return { session: data.session, user, profile };
  };

  RR.getOpenApi = async () => {
    if (RR._openApi) return RR._openApi;

    const { data } = await supabaseClient.auth.getSession();
    const accessToken = data?.session?.access_token || SUPABASE_ANON_KEY;

    const response = await fetch(`${SUPABASE_URL}/rest/v1/`, {
      headers: {
        apikey: SUPABASE_ANON_KEY,
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/openapi+json"
      }
    });

    if (!response.ok) {
      throw new Error("Database structure could not be read.");
    }

    RR._openApi = await response.json();
    return RR._openApi;
  };

  RR.getTableColumns = async (table) => {
    const spec = await RR.getOpenApi();
    const schema =
      spec?.definitions?.[table] ||
      spec?.components?.schemas?.[table] ||
      {};
    return new Set(Object.keys(schema.properties || {}));
  };

  RR.pickColumn = (columns, aliases) =>
    aliases.find((name) => columns.has(name)) || null;

  RR.filterPayload = (payload, columns) =>
    Object.fromEntries(
      Object.entries(payload).filter(
        ([key, value]) => columns.has(key) && value !== undefined
      )
    );

  RR.safeFileName = (name) =>
    String(name || "image")
      .toLowerCase()
      .replace(/[^a-z0-9._-]/g, "_");

  RR.uploadMedia = async ({
    file,
    entityType,
    entityId,
    mediaCategory = "reference",
    sourceType = "gallery",
    visibilityScope = "factory",
    caption = ""
  }) => {
    if (!file) return null;

    const path = [
      entityType,
      String(entityId),
      `${Date.now()}-${crypto.randomUUID()}-${RR.safeFileName(file.name)}`
    ].join("/");

    const { error: uploadError } = await supabaseClient.storage
      .from("redzed-media")
      .upload(path, file, {
        cacheControl: "3600",
        contentType: file.type || undefined,
        upsert: false
      });

    if (uploadError) throw uploadError;

    const { data: publicData } = supabaseClient.storage
      .from("redzed-media")
      .getPublicUrl(path);

    const columns = await RR.getTableColumns("rr_media");
    const payload = RR.filterPayload({
      entity_type: entityType,
      entity_id: String(entityId),
      media_category: mediaCategory,
      file_url: publicData.publicUrl,
      storage_path: path,
      file_name: file.name,
      mime_type: file.type || null,
      caption,
      source_type: sourceType,
      visibility_scope: visibilityScope,
      is_cover: false,
      sort_order: 0
    }, columns);

    const { data, error } = await supabaseClient
      .from("rr_media")
      .insert(payload)
      .select()
      .single();

    if (error) throw error;
    return data;
  };

  RR.getMediaMap = async (entityType, category) => {
    let query = supabaseClient
      .from("rr_media")
      .select("*")
      .eq("entity_type", entityType)
      .order("sort_order", { ascending: true })
      .order("created_at", { ascending: true });

    if (category) query = query.eq("media_category", category);

    const { data, error } = await query;
    if (error) throw error;

    return (data || []).reduce((map, item) => {
      const key = String(item.entity_id);
      if (!map[key]) map[key] = [];
      map[key].push(item);
      return map;
    }, {});
  };

  window.RR = RR;
})();
