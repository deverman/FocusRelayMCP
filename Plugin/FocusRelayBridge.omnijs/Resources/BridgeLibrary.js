(() => {
  /*
   * OmniFocus API Contract
   * ======================
   * 
   * This file interacts with OmniFocus's JavaScript API. To ensure consistency
   * and correctness, we MUST use OmniFocus's native status properties instead
   * of manual heuristics.
   * 
   * TASK STATUS (Task.taskStatus)
   * -----------------------------
   * - Task.Status.Available    - Task is actionable now
   * - Task.Status.Next         - Next action in a sequential project
   * - Task.Status.DueSoon      - Task is due within the next 24 hours
   * - Task.Status.Overdue      - Task's due date has passed
   * - Task.Status.Blocked      - Task is blocked by incomplete prerequisites
   * - Task.Status.Completed    - Task is marked complete
   * - Task.Status.Dropped      - Task has been dropped
   * 
   * PROJECT STATUS (Project.status)
   * -------------------------------
   * - Project.Status.Active    - Project is active and actionable
   * - Project.Status.OnHold    - Project is on hold (tasks not available)
   * - Project.Status.Dropped   - Project has been dropped
   * - Project.Status.Done      - Project is completed
   * 
   * KEY PRINCIPLES
   * --------------
   * 1. ALWAYS use task.taskStatus for availability checks
   * 2. ALWAYS check project.status before considering a task available
   * 3. NEVER manually check defer dates - OmniFocus handles this via taskStatus
   * 4. ALWAYS respect parent task status (completed/dropped parents block children)
   * 
   * Status Helper Functions (defined below):
   * - taskStatus(task)          - Get task status safely
   * - isRemainingStatus(task)   - Check if task is not completed/dropped
   * - isAvailableStatus(task)   - Check if task is actionable (Available/Next/DueSoon/Overdue)
   * - projectMatchesView()      - Check if project matches view filter
   * - isTaskAvailable()         - Full availability check including project/parent status
   */
  
  const lib = new PlugIn.Library(new Version("1.0"));

  lib.handleRequest = function(requestId, basePath) {
    const requestPath = basePath + "/requests/" + requestId + ".json";
    const responsePath = basePath + "/responses/" + requestId + ".json";
    const lockPath = basePath + "/locks/" + requestId + ".lock";
    
      function safe(fn) {
        try { return fn(); } catch (e) { return null; }
      }

      function ensureDir(path) {
        try {
          const url = URL.fromString("file://" + path);
          const wrapper = FileWrapper.fromURL(url);
          if (wrapper.type === FileWrapper.Type.Directory) { return; }
        } catch (e) {}
        const url = URL.fromString("file://" + path);
        const dir = FileWrapper.withChildren(null, []);
        dir.write(url, [FileWrapper.WritingOptions.Atomic], null);
      }

    function readJSON(path) {
      const url = URL.fromString("file://" + path);
      const wrapper = FileWrapper.fromURL(url);
      return JSON.parse(wrapper.contents.toString());
    }

    function fileExists(path) {
      try {
        const url = URL.fromString("file://" + path);
        FileWrapper.fromURL(url);
        return true;
      } catch (e) {
        return false;
      }
    }

    function writeJSON(path, obj) {
      const url = URL.fromString("file://" + path);
      const data = Data.fromString(JSON.stringify(obj));
      const wrapper = FileWrapper.withContents(null, data);
      wrapper.write(url, [FileWrapper.WritingOptions.Atomic], null);
    }

    function writeLock(path) {
      const url = URL.fromString("file://" + path);
      const data = Data.fromString(JSON.stringify({ ts: Date.now() }));
      const wrapper = FileWrapper.withContents(null, data);
      wrapper.write(url, [FileWrapper.WritingOptions.Atomic], null);
    }

    function removeFile(path) {
      try {
        const url = URL.fromString("file://" + path);
        const wrapper = FileWrapper.fromURL(url);
        wrapper.remove();
      } catch (e) {}
    }

    function taskToPayload(t, fields) {
      const hasField = (name) => fields.length === 0 || fields.indexOf(name) !== -1;
      const project = hasField("projectID") || hasField("projectName") ? safe(() => t.containingProject) : null;
      const tags = (hasField("tagIDs") || hasField("tagNames")) ? (safe(() => t.tags) || []) : [];
      const dueDate = hasField("dueDate") ? safe(() => t.dueDate) : null;
      const deferDate = hasField("deferDate") ? safe(() => t.deferDate) : null;

      return {
        id: hasField("id") ? String(safe(() => t.id.primaryKey) || "") : null,
        name: hasField("name") ? String(safe(() => t.name) || "") : null,
        note: hasField("note") ? safe(() => t.note) : null,
        projectID: hasField("projectID") && project ? String(safe(() => project.id.primaryKey) || "") : null,
        projectName: hasField("projectName") && project ? String(safe(() => project.name) || "") : null,
        tagIDs: hasField("tagIDs") ? tags.map(tag => String(safe(() => tag.id.primaryKey) || "")) : null,
        tagNames: hasField("tagNames") ? tags.map(tag => String(safe(() => tag.name) || "")) : null,
        dueDate: hasField("dueDate") && dueDate ? dueDate.toISOString() : null,
        deferDate: hasField("deferDate") && deferDate ? deferDate.toISOString() : null,
        completionDate: hasField("completionDate") ? (safe(() => t.completionDate) ? t.completionDate.toISOString() : null) : null,
        completed: hasField("completed") ? Boolean(t.completed) : null,
        flagged: hasField("flagged") ? Boolean(t.flagged) : null,
        estimatedMinutes: hasField("estimatedMinutes") ? t.estimatedMinutes : null,
        available: hasField("available") ? isTaskAvailable(t) : null
      };
    }

    // ============================================================
    // STATUS MODULE - Single Source of Truth for OmniFocus Status
    // ============================================================
    // 
    // These functions provide the ONLY way to check task and project
    // status. Do NOT use manual checks elsewhere in the codebase.
    // 
    // Task Status Values (Task.Status.*):
    //   Available, Next, DueSoon, Overdue, Blocked, Completed, Dropped
    //
    // Project Status Values (Project.Status.*):
    //   Active, OnHold, Dropped, Done
    // ============================================================

    /**
     * Get the native task status from OmniFocus
     * @param {Task} task - OmniFocus task object
     * @returns {string|null} Task status or null if unavailable
     */
    function taskStatus(task) {
      return safe(() => task.taskStatus);
    }

    /**
     * Check if task is remaining (not completed or dropped)
     * @param {Task} task - OmniFocus task object  
     * @returns {boolean} True if task is remaining
     */
    function isRemainingStatus(task) {
      const st = taskStatus(task);
      return st !== Task.Status.Completed && st !== Task.Status.Dropped;
    }

    /**
     * Check if task status indicates availability
     * Note: This checks ONLY the task status, not project/parent status
     * @param {Task} task - OmniFocus task object
     * @returns {boolean} True if task has an available status
     */
    function isAvailableStatus(task) {
      const st = taskStatus(task);
      return st === Task.Status.Available ||
        st === Task.Status.DueSoon ||
        st === Task.Status.Next ||
        st === Task.Status.Overdue;
    }

    /**
     * Check if a project matches the requested view filter
     * @param {Project} project - OmniFocus project object
     * @param {string} view - View filter: "active", "onHold", "dropped", "done", "everything", "all"
     * @param {boolean} allowOnHoldInEverything - Whether to include on-hold projects in "everything" view
     * @returns {boolean} True if project matches the view
     */
    function projectMatchesView(project, view, allowOnHoldInEverything) {
      if (!project) { return false; }
      if (!view || view === "all") { return true; }

      const normalizedView = view.toLowerCase();
      const allowOnHold = allowOnHoldInEverything && normalizedView === "everything";

      const status = safe(() => project.status);
      if (status === Project.Status.Active) { return normalizedView === "active"; }
      if (status === Project.Status.OnHold) { return allowOnHold || normalizedView === "onhold" || normalizedView === "on_hold"; }
      if (status === Project.Status.Dropped) { return normalizedView === "dropped"; }
      if (status === Project.Status.Done) { return normalizedView === "done" || normalizedView === "completed"; }

      // Fallback string matching for safety
      const statusStr = String(status);
      if (statusStr.includes("OnHold")) { return allowOnHold || normalizedView === "onhold" || normalizedView === "on_hold"; }
      if (statusStr.includes("Dropped")) { return normalizedView === "dropped"; }
      if (statusStr.includes("Done")) { return normalizedView === "done" || normalizedView === "completed"; }

      return normalizedView === "active";
    }

    /**
     * Check if a task is truly available (respects project and parent status)
     * This is the PRIMARY function for checking task availability.
     * 
     * A task is available ONLY if:
     * 1. Its project is active (not onHold/dropped/done)
     * 2. Its parent task (if any) is not completed/dropped
     * 3. Its own status is Available, Next, DueSoon, or Overdue
     * 
     * @param {Task} task - OmniFocus task object
     * @returns {boolean} True if task is available for action
     */
    function isTaskAvailable(task) {
      // Check project status first
      const project = safe(() => task.containingProject);
      if (project) {
        const status = safe(() => project.status);
        if (status === Project.Status.OnHold) { return false; }
        if (status === Project.Status.Dropped) { return false; }
        if (status === Project.Status.Done) { return false; }

        // Fallback string matching for safety
        const statusStr = String(status);
        if (statusStr.includes("OnHold")) { return false; }
        if (statusStr.includes("Dropped")) { return false; }
        if (statusStr.includes("Done")) { return false; }

        // Additional safety checks
        if (Boolean(safe(() => project.completed))) { return false; }
        if (safe(() => project.dropDate)) { return false; }
        if (Boolean(safe(() => project.onHold))) { return false; }
      }

      // Check parent task status
      const parent = safe(() => task.parent);
      if (parent) {
        if (Boolean(safe(() => parent.completed))) { return false; }
        if (safe(() => parent.dropDate)) { return false; }
      }

      // Finally check the task's own status
      return isAvailableStatus(task);
    }

    // ============================================================
    // END STATUS MODULE
    // ============================================================

    // Date parsing helper - available to all operations
    function parseFilterDate(dateString, warnings) {
      if (!dateString || typeof dateString !== "string") return null;
      const parsed = new Date(dateString);
      if (isNaN(parsed.getTime())) {
        warnings.push("Invalid date filter value: " + dateString);
        return null;
      }
      return parsed;
    }

    // Helper to get task date safely and convert to timestamp for comparison
    function getTaskDateTimestamp(task, dateGetter) {
      const date = safe(() => dateGetter(task));
      if (!date) return null;
      if (typeof date.getTime !== "function") return null;
      const ts = date.getTime();
      if (isNaN(ts)) return null;
      return ts;
    }

    // Helper to get project date safely
    function getProjectDateTimestamp(project, dateGetter) {
      const date = safe(() => dateGetter(project));
      if (!date) return null;
      if (typeof date.getTime !== "function") return null;
      const ts = date.getTime();
      if (isNaN(ts)) return null;
      return ts;
    }

      const start = Date.now();
      const response = { schemaVersion: 1, requestId: requestId, ok: true, data: null, timingMs: null, warnings: [] };

      try {
        ensureDir(basePath);
        ensureDir(basePath + "/requests");
        ensureDir(basePath + "/responses");
        ensureDir(basePath + "/locks");
        ensureDir(basePath + "/logs");
      if (fileExists(responsePath)) { return; }
      writeLock(lockPath);
      const request = readJSON(requestPath);
        if (request.op === "ping") {
          response.data = { ok: true, plugin: "FocusRelay Bridge", version: "0.1.0" };
        } else if (request.op === "list_inbox" || request.op === "list_tasks") {
          const filter = request.filter || {};
          const fields = request.fields || [];
          const hasField = (name) => fields.length === 0 || fields.indexOf(name) !== -1;

          let tasks = [];
          const useInbox = filter.inboxOnly === true || request.op === "list_inbox";
          if (useInbox) {
            inbox.apply(task => tasks.push(task));
          } else {
            tasks = flattenedTasks;
          }

          if (!useInbox && typeof filter.project === "string" && filter.project.length > 0) {
            const projectFilter = filter.project;
            tasks = tasks.filter(t => {
              const project = safe(() => t.containingProject);
              if (!project) { return false; }
              const pid = String(safe(() => project.id.primaryKey) || "");
              const pname = String(safe(() => project.name) || "");
              return pid === projectFilter || pname === projectFilter;
            });
          }
          // Note: When inboxOnly is false and no project filter is specified,
          // we return tasks from all projects (flattenedTasks)

          const inboxView = (typeof filter.inboxView === "string") ? filter.inboxView.toLowerCase() : "available";
          const isEverything = inboxView === "everything";
          const isRemaining = inboxView === "remaining";

          if (typeof filter.completed === "boolean") {
            tasks = tasks.filter(t => Boolean(t.completed) === filter.completed);
          } else if (!isEverything) {
            tasks = tasks.filter(t => isRemainingStatus(t));
          }

          const availableOnly = (typeof filter.availableOnly === "boolean")
            ? filter.availableOnly
            : (filter.completed === true ? false : !isRemaining && !isEverything);
          if (availableOnly) {
            tasks = tasks.filter(t => isTaskAvailable(t));
          }

          // Timezone-aware date calculations
          // Get user's timezone from request, fallback to local
          const userTimeZone = request.userTimeZone || Intl.DateTimeFormat().resolvedOptions().timeZone;
          
          // Helper to create date in user's timezone and convert to UTC
          function getLocalDate(hour, minute, timeZone) {
            const now = new Date();
            const localDateStr = now.toLocaleString('en-US', {
              timeZone: timeZone,
              year: 'numeric',
              month: '2-digit',
              day: '2-digit',
              hour: '2-digit',
              minute: '2-digit',
              second: '2-digit',
              hour12: false
            });
            // Parse the local date string
            const [datePart, timePart] = localDateStr.split(', ');
            const [month, day, year] = datePart.split('/');
            const [h, m, s] = timePart.split(':');
            
            // Create date object and set the desired time
            const date = new Date(`${year}-${month}-${day}T${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}:00`);
            return date;
          }
          
          // Batch all filters into single pass for performance
          // Pre-parse all filter dates once
          const filterState = {
            // Status filters
            completed: filter.completed,
            flagged: filter.flagged,
            availableOnly: filter.availableOnly,
            
            // Project filter
            projectFilter: filter.project,
            
            // Date filters (pre-parsed)
            dueBefore: filter.dueBefore ? parseFilterDate(filter.dueBefore, response.warnings) : null,
            dueAfter: filter.dueAfter ? parseFilterDate(filter.dueAfter, response.warnings) : null,
            deferBefore: filter.deferBefore ? parseFilterDate(filter.deferBefore, response.warnings) : null,
            deferAfter: filter.deferAfter ? parseFilterDate(filter.deferAfter, response.warnings) : null,
            completedBefore: filter.completedBefore ? parseFilterDate(filter.completedBefore, response.warnings) : null,
            completedAfter: filter.completedAfter ? parseFilterDate(filter.completedAfter, response.warnings) : null,
            
            // Duration filters
            maxEstimatedMinutes: filter.maxEstimatedMinutes,
            minEstimatedMinutes: filter.minEstimatedMinutes,
            
            // Tag filters
            tags: Array.isArray(filter.tags) ? filter.tags : null,
            untaggedOnly: Array.isArray(filter.tags) && filter.tags.length === 0
          };
          
          const projectView = (typeof filter.projectView === "string") ? filter.projectView.toLowerCase() : null;
          const isEverythingView = projectView === "everything";

          // Helper function to check if a task matches all filters
          function taskMatchesFilters(t) {
            // Status checks
            if (filterState.completed !== undefined) {
              const taskCompleted = Boolean(t.completed);
              if (taskCompleted !== filterState.completed) return false;
            }
            if (filterState.flagged !== undefined) {
              const taskFlagged = Boolean(t.flagged);
              if (taskFlagged !== filterState.flagged) return false;
            }
            if (filterState.availableOnly) {
              if (!isTaskAvailable(t)) return false;
            }
            
            // Project check
            const project = safe(() => t.containingProject);
            if (filterState.projectFilter) {
              if (!project) return false;
              const pid = String(safe(() => project.id.primaryKey) || "");
              const pname = String(safe(() => project.name) || "");
              if (pid !== filterState.projectFilter && pname !== filterState.projectFilter) return false;
            }
            if (projectView) {
              if (!projectMatchesView(project, projectView, true)) return false;
            }
            
            // Date checks
            if (filterState.dueBefore) {
              const due = getTaskDateTimestamp(t, task => task.dueDate);
              if (due === null || due > filterState.dueBefore.getTime()) return false;
            }
            if (filterState.dueAfter) {
              const due = getTaskDateTimestamp(t, task => task.dueDate);
              if (due === null || due < filterState.dueAfter.getTime()) return false;
            }
            if (filterState.deferBefore) {
              const defer = getTaskDateTimestamp(t, task => task.deferDate);
              if (defer === null || defer > filterState.deferBefore.getTime()) return false;
            }
            if (filterState.deferAfter) {
              const defer = getTaskDateTimestamp(t, task => task.deferDate);
              if (defer === null || defer < filterState.deferAfter.getTime()) return false;
            }
            
            // Completion date checks
            if (filterState.completedBefore) {
              const completed = getTaskDateTimestamp(t, task => task.completionDate);
              if (completed === null || completed > filterState.completedBefore.getTime()) return false;
            }
            if (filterState.completedAfter) {
              const completed = getTaskDateTimestamp(t, task => task.completionDate);
              if (completed === null || completed < filterState.completedAfter.getTime()) return false;
            }
            
            // Duration checks
            if (filterState.maxEstimatedMinutes !== undefined) {
              const minutes = safe(() => t.estimatedMinutes);
              if (minutes === null || minutes === undefined || minutes > filterState.maxEstimatedMinutes) return false;
            }
            if (filterState.minEstimatedMinutes !== undefined) {
              const minutes = safe(() => t.estimatedMinutes);
              if (minutes === null || minutes === undefined || minutes < filterState.minEstimatedMinutes) return false;
            }
            
            // Tag checks
            if (filterState.tags) {
              const tags = safe(() => t.tags) || [];
              if (filterState.untaggedOnly) {
                if (tags.length > 0) return false;
              } else {
                const hasMatchingTag = tags.some(tag => {
                  const tagId = String(safe(() => tag.id.primaryKey) || "");
                  const tagName = String(safe(() => tag.name) || "");
                  return filterState.tags.some(filterTag => tagId === filterTag || tagName === filterTag);
                });
                if (!hasMatchingTag) return false;
              }
            }
            
            return true;
          }
          
          // Check if total count is requested
          const includeTotalCount = filter.includeTotalCount === true;
          
          // Calculate total count if requested (requires scanning all tasks)
          let totalCount = null;
          if (includeTotalCount) {
            totalCount = 0;
            for (const t of tasks) {
              if (taskMatchesFilters(t)) {
                totalCount++;
              }
            }
          }
          
          // Single-pass filter with pagination (only collect up to limit)
          const filteredTasks = [];
          const limit = request.page && request.page.limit ? request.page.limit : 50;
          
          for (let i = 0; i < tasks.length && filteredTasks.length < limit; i++) {
            const t = tasks[i];
            if (taskMatchesFilters(t)) {
              filteredTasks.push(t);
            }
          }
          
          tasks = filteredTasks;

          // Sort by completion date descending when filtering by completed tasks
          // This matches OmniFocus Completed perspective behavior
          if (filterState.completed === true || filterState.completedAfter || filterState.completedBefore) {
            tasks.sort((a, b) => {
              const dateA = getTaskDateTimestamp(a, t => t.completionDate) || 0;
              const dateB = getTaskDateTimestamp(b, t => t.completionDate) || 0;
              return dateB - dateA;
            });
          }

          // Apply offset for pagination (tasks already limited to page size during filtering)
          const offset = request.page && request.page.cursor ? parseInt(request.page.cursor, 10) : 0;
          const pageTasks = offset > 0 ? tasks.slice(offset) : tasks;
          const items = pageTasks.map(t => taskToPayload(t, fields));
          
          // Calculate returned count (actual items in this response)
          const returnedCount = items.length;
          
          // Calculate pagination cursor
          const hasMore = items.length === limit;
          const nextCursor = hasMore ? String(offset + items.length) : null;
          
          // Build response with both counts
          response.data = { items: items, nextCursor: nextCursor, returnedCount: returnedCount };
          if (includeTotalCount) {
            response.data.totalCount = totalCount;
          }
        } else if (request.op === "list_projects") {
          const fields = request.fields || [];
          const hasField = (name) => fields.length === 0 || fields.indexOf(name) !== -1;
          // Check both projectFilter and filter (Swift sends projectFilter)
          const filter = request.projectFilter || request.filter || {};
          const statusFilter = (typeof filter.statusFilter === "string") ? filter.statusFilter.toLowerCase() : "active";
          const includeTaskCounts = filter.includeTaskCounts === true;
          const reviewPerspective = filter.reviewPerspective === true;

          const reviewDueBefore = parseFilterDate(filter.reviewDueBefore, response.warnings);
          const reviewDueAfter = parseFilterDate(filter.reviewDueAfter, response.warnings);
          const reviewCutoff = reviewDueBefore || (reviewPerspective ? new Date() : null);
          
          let projects = flattenedProjects;
          
          // Filter by status using Project.Status enum
          if (reviewPerspective) {
            projects = projects.filter(p => {
              const status = safe(() => p.status);
              if (!status) return false;
              return status !== Project.Status.Dropped && status !== Project.Status.Done;
            });
          } else if (statusFilter !== "all") {
            projects = projects.filter(p => {
              const status = safe(() => p.status);
              if (!status) return false;
              
              if (statusFilter === "active") {
                return status === Project.Status.Active;
              } else if (statusFilter === "onhold" || statusFilter === "on_hold") {
                return status === Project.Status.OnHold;
              } else if (statusFilter === "dropped") {
                return status === Project.Status.Dropped;
              } else if (statusFilter === "done" || statusFilter === "completed") {
                return status === Project.Status.Done;
              }
              return true;
            });
          }

          if (reviewCutoff || reviewDueAfter) {
            projects = projects.filter(p => {
              const nextReview = getProjectDateTimestamp(p, project => project.nextReviewDate);
              if (nextReview === null) return false;
              if (reviewCutoff && nextReview > reviewCutoff.getTime()) return false;
              if (reviewDueAfter && nextReview < reviewDueAfter.getTime()) return false;
              return true;
            });
          }

          // Completion date filtering for projects
          const projectFilter = request.projectFilter || {};
          const completedAfter = projectFilter.completedAfter ? parseFilterDate(projectFilter.completedAfter, response.warnings) : null;
          const completedBefore = projectFilter.completedBefore ? parseFilterDate(projectFilter.completedBefore, response.warnings) : null;
          const completedOnly = projectFilter.completed === true;

          if (completedOnly || completedAfter || completedBefore) {
            projects = projects.filter(p => {
              const status = safe(() => p.status);
              // Only include completed projects (status = Done), exclude dropped
              if (status !== Project.Status.Done) return false;

              const completionDate = getProjectDateTimestamp(p, project => project.completionDate);
              if (completionDate === null) return false;

              if (completedAfter && completionDate < completedAfter.getTime()) return false;
              if (completedBefore && completionDate > completedBefore.getTime()) return false;

              return true;
            });

            // Sort by completion date descending (most recent first) - matches OmniFocus Completed perspective
            projects.sort((a, b) => {
              const dateA = getProjectDateTimestamp(a, p => p.completionDate) || 0;
              const dateB = getProjectDateTimestamp(b, p => p.completionDate) || 0;
              return dateB - dateA;
            });
          }

          const limit = request.page && request.page.limit ? request.page.limit : 150;
          let offset = 0;
          if (request.page && request.page.cursor) {
            const parsed = parseInt(request.page.cursor, 10);
            if (!isNaN(parsed) && parsed >= 0) { offset = parsed; }
          }
          
          const slice = projects.slice(offset, offset + limit);
          
          const items = slice.map(p => {
            const lastReviewDate = hasField("lastReviewDate") ? safe(() => p.lastReviewDate) : null;
            const nextReviewDate = hasField("nextReviewDate") ? safe(() => p.nextReviewDate) : null;
            const reviewInterval = hasField("reviewInterval") ? safe(() => p.reviewInterval) : null;
            let reviewIntervalPayload = null;
            if (reviewInterval) {
              const steps = safe(() => reviewInterval.steps);
              const unit = safe(() => reviewInterval.unit);
              reviewIntervalPayload = {
                steps: (typeof steps === "number" && isFinite(steps)) ? Math.trunc(steps) : null,
                unit: unit ? String(unit) : null
              };
            }

            // Convert Project.Status enum to string
            function getProjectStatusString(project) {
              const status = safe(() => project.status);
              if (!status) return "active";
              
              if (project.status === Project.Status.Active) return "active";
              if (project.status === Project.Status.OnHold) return "onHold";
              if (project.status === Project.Status.Dropped) return "dropped";
              if (project.status === Project.Status.Done) return "done";
              
              // Fallback: parse from string representation
              const statusStr = String(status);
              if (statusStr.includes("OnHold")) return "onHold";
              if (statusStr.includes("Dropped")) return "dropped";
              if (statusStr.includes("Done")) return "done";
              return "active";
            }
            
            const completionDate = hasField("completionDate") ? safe(() => p.completionDate) : null;

            const item = {
              id: hasField("id") ? String(safe(() => p.id.primaryKey) || "") : null,
              name: hasField("name") ? String(safe(() => p.name) || "") : null,
              note: hasField("note") ? safe(() => p.note) : null,
              status: hasField("status") ? getProjectStatusString(p) : null,
              flagged: hasField("flagged") ? Boolean(p.flagged) : null,
              lastReviewDate: hasField("lastReviewDate") && lastReviewDate ? lastReviewDate.toISOString() : null,
              nextReviewDate: hasField("nextReviewDate") && nextReviewDate ? nextReviewDate.toISOString() : null,
              reviewInterval: hasField("reviewInterval") ? reviewIntervalPayload : null,
              completionDate: hasField("completionDate") && completionDate ? completionDate.toISOString() : null
            };
            
            // Calculate task counts from flattenedTasks
            if (includeTaskCounts) {
              const flattenedTasks = safe(() => p.flattenedTasks) || [];
              
              // Count tasks by status
              let available = 0;
              let remaining = 0;
              let completed = 0;
              let dropped = 0;
              
              for (const task of flattenedTasks) {
                const taskStatus = safe(() => task.taskStatus);
                if (taskStatus === Task.Status.Completed) {
                  completed++;
                } else if (taskStatus === Task.Status.Dropped) {
                  dropped++;
                } else {
                  remaining++;
                  if (taskStatus === Task.Status.Available || taskStatus === Task.Status.Next) {
                    available++;
                  }
                }
              }
              
              item.availableTasks = available;
              item.remainingTasks = remaining;
              item.completedTasks = completed;
              item.droppedTasks = dropped;
              item.totalTasks = flattenedTasks.length;

            }
            
            // Add hasChildren for stalled project detection
            if (hasField("hasChildren")) {
              const flattenedTasks = safe(() => p.flattenedTasks) || [];
              item.hasChildren = flattenedTasks.length > 0;
            }
            
            // Add containsSingletonActions to identify Single Actions projects
            if (hasField("containsSingletonActions")) {
              item.containsSingletonActions = Boolean(safe(() => p.containsSingletonActions));
            }
            
            // Add nextTask for stalled project detection (null if no available actions)
            if (hasField("nextTask")) {
              const nextTask = safe(() => p.nextTask);
              item.nextTask = nextTask ? {
                id: String(safe(() => nextTask.id.primaryKey) || ""),
                name: String(safe(() => nextTask.name) || "")
              } : null;
            }
            
            // Add isStalled field - true if has tasks but no nextTask AND not Single Actions
            if (hasField("isStalled")) {
              const flattenedTasks = safe(() => p.flattenedTasks) || [];
              const hasTasks = flattenedTasks.length > 0;
              const nextTask = safe(() => p.nextTask);
              const isSingleActions = Boolean(safe(() => p.containsSingletonActions));
              item.isStalled = hasTasks && !nextTask && !isSingleActions;
            }
            
            return item;
          });
          
          const nextCursor = (offset + limit < projects.length) ? String(offset + limit) : null;
          const returnedCount = items.length;
          response.data = { items: items, nextCursor: nextCursor, returnedCount: returnedCount, totalCount: projects.length };
        } else if (request.op === "list_tags") {
          // Check both filter and tagFilter (Swift sends tagFilter)
          const filter = request.tagFilter || request.filter || {};
          const statusFilter = (typeof filter.statusFilter === "string") ? filter.statusFilter.toLowerCase() : "active";
          const includeTaskCounts = filter.includeTaskCounts === true;
          
          let tags = flattenedTags;
          
          // Filter by status
          if (statusFilter !== "all") {
            tags = tags.filter(tag => {
              const status = safe(() => tag.status);
              if (!status) return false;
              
              if (statusFilter === "active") {
                return status === Tag.Status.Active;
              } else if (statusFilter === "onhold" || statusFilter === "on_hold") {
                return status === Tag.Status.OnHold;
              } else if (statusFilter === "dropped") {
                return status === Tag.Status.Dropped;
              }
              return true;
            });
          }
          
          const limit = request.page && request.page.limit ? request.page.limit : 150;
          let offset = 0;
          if (request.page && request.page.cursor) {
            const parsed = parseInt(request.page.cursor, 10);
            if (!isNaN(parsed) && parsed >= 0) { offset = parsed; }
          }
          
          const slice = tags.slice(offset, offset + limit);
          const items = slice.map(tag => {
            // Convert Tag.Status enum to string - check directly on tag object
            function getTagStatusString(tag) {
              const status = safe(() => tag.status);
              if (!status) return "active";
              // Handle both enum comparison and string representation
              if (tag.status === Tag.Status.Active) return "active";
              if (tag.status === Tag.Status.OnHold) return "onHold";
              if (tag.status === Tag.Status.Dropped) return "dropped";
              // Fallback: try to parse from string representation
              const statusStr = String(status);
              if (statusStr.includes("OnHold")) return "onHold";
              if (statusStr.includes("Dropped")) return "dropped";
              return "active";
            }
            
            const item = {
              id: String(safe(() => tag.id.primaryKey) || ""),
              name: String(safe(() => tag.name) || ""),
              status: getTagStatusString(tag)
            };
            
            // Get task counts using OmniFocus built-in properties
            // Note: Per documentation, cleanUp() should be called for accurate counts
            const availableTasks = safe(() => tag.availableTasks);
            const remainingTasks = safe(() => tag.remainingTasks);
            const allTasks = safe(() => tag.tasks);
            
            item.availableTasks = availableTasks ? availableTasks.length : 0;
            item.remainingTasks = remainingTasks ? remainingTasks.length : 0;
            item.totalTasks = allTasks ? allTasks.length : 0;
            
            return item;
          });
          
          const nextCursor = (offset + limit < tags.length) ? String(offset + limit) : null;
          const returnedCount = items.length;
          response.data = { items: items, nextCursor: nextCursor, returnedCount: returnedCount, totalCount: tags.length };
        } else if (request.op === "get_task") {
          const fields = request.fields || [];
          const taskId = request.id;
          if (!taskId) {
            response.ok = false;
            response.error = { code: "MISSING_ID", message: "Task id is required" };
          } else {
            const match = Task.byIdentifier(String(taskId));
            if (!match) {
              response.ok = false;
              response.error = { code: "NOT_FOUND", message: "Task not found" };
            } else {
              response.data = taskToPayload(match, fields);
            }
          }
        } else if (request.op === "get_task_counts") {
          const filter = request.filter || {};

          // Use same filtering logic as list_tasks for consistency
          let tasks = flattenedTasks;

          // Filter by inbox only if specified
          if (filter.inboxOnly === true) {
            tasks = [];
            inbox.apply(task => tasks.push(task));
          }

          const inboxView = (typeof filter.inboxView === "string") ? filter.inboxView.toLowerCase() : "available";
          const isEverything = inboxView === "everything";
          const isRemaining = inboxView === "remaining";

          if (typeof filter.completed === "boolean") {
            tasks = tasks.filter(t => Boolean(t.completed) === filter.completed);
          } else if (!isEverything) {
            tasks = tasks.filter(t => isRemainingStatus(t));
          }

          const availableOnly = (typeof filter.availableOnly === "boolean")
            ? filter.availableOnly
            : (filter.completed === true ? false : !isRemaining && !isEverything);
          if (availableOnly) {
            tasks = tasks.filter(t => isTaskAvailable(t));
          }

          // Parse filter dates
          const filterState = {
            completed: filter.completed,
            flagged: filter.flagged,
            availableOnly: availableOnly,
            projectFilter: filter.project,
            dueBefore: filter.dueBefore ? parseFilterDate(filter.dueBefore, response.warnings) : null,
            dueAfter: filter.dueAfter ? parseFilterDate(filter.dueAfter, response.warnings) : null,
            deferBefore: filter.deferBefore ? parseFilterDate(filter.deferBefore, response.warnings) : null,
            deferAfter: filter.deferAfter ? parseFilterDate(filter.deferAfter, response.warnings) : null,
            completedBefore: filter.completedBefore ? parseFilterDate(filter.completedBefore, response.warnings) : null,
            completedAfter: filter.completedAfter ? parseFilterDate(filter.completedAfter, response.warnings) : null,
            tags: Array.isArray(filter.tags) ? filter.tags : null,
            untaggedOnly: Array.isArray(filter.tags) && filter.tags.length === 0,
            maxEstimatedMinutes: filter.maxEstimatedMinutes,
            minEstimatedMinutes: filter.minEstimatedMinutes
          };

          const projectView = (typeof filter.projectView === "string") ? filter.projectView.toLowerCase() : null;

          // Apply filters
          tasks = tasks.filter(t => {
            const project = safe(() => t.containingProject);

            if (filterState.completed !== undefined) {
              const taskCompleted = Boolean(t.completed);
              if (taskCompleted !== filterState.completed) return false;
            } else if (!isEverything) {
              if (!isRemainingStatus(t)) return false;
            }
            if (filterState.flagged !== undefined) {
              const taskFlagged = Boolean(t.flagged);
              if (taskFlagged !== filterState.flagged) return false;
            }
            if (filterState.availableOnly) {
              if (!isTaskAvailable(t)) return false;
            }
            if (filterState.projectFilter) {
              if (!project) return false;
              const pid = String(safe(() => project.id.primaryKey) || "");
              const pname = String(safe(() => project.name) || "");
              if (pid !== filterState.projectFilter && pname !== filterState.projectFilter) return false;
            }
            if (projectView) {
              if (!projectMatchesView(project, projectView, true)) return false;
            }
            if (filterState.dueBefore) {
              const due = getTaskDateTimestamp(t, task => task.dueDate);
              if (due === null || due > filterState.dueBefore.getTime()) return false;
            }
            if (filterState.dueAfter) {
              const due = getTaskDateTimestamp(t, task => task.dueDate);
              if (due === null || due < filterState.dueAfter.getTime()) return false;
            }
            if (filterState.deferBefore) {
              const defer = getTaskDateTimestamp(t, task => task.deferDate);
              if (defer === null || defer > filterState.deferBefore.getTime()) return false;
            }
            if (filterState.deferAfter) {
              const defer = getTaskDateTimestamp(t, task => task.deferDate);
              if (defer === null || defer < filterState.deferAfter.getTime()) return false;
            }
            if (filterState.completedBefore) {
              const completed = getTaskDateTimestamp(t, task => task.completionDate);
              if (completed === null || completed > filterState.completedBefore.getTime()) return false;
            }
            if (filterState.completedAfter) {
              const completed = getTaskDateTimestamp(t, task => task.completionDate);
              if (completed === null || completed < filterState.completedAfter.getTime()) return false;
            }
            if (filterState.maxEstimatedMinutes !== undefined) {
              const minutes = safe(() => t.estimatedMinutes);
              if (minutes === null || minutes === undefined || minutes > filterState.maxEstimatedMinutes) return false;
            }
            if (filterState.minEstimatedMinutes !== undefined) {
              const minutes = safe(() => t.estimatedMinutes);
              if (minutes === null || minutes === undefined || minutes < filterState.minEstimatedMinutes) return false;
            }
            if (filterState.tags) {
              const tags = safe(() => t.tags) || [];
              if (filterState.untaggedOnly) {
                if (tags.length > 0) return false;
              } else {
                const hasMatchingTag = tags.some(tag => {
                  const tagId = String(safe(() => tag.id.primaryKey) || "");
                  const tagName = String(safe(() => tag.name) || "");
                  return filterState.tags.some(filterTag => tagId === filterTag || tagName === filterTag);
                });
                if (!hasMatchingTag) return false;
              }
            }
            return true;
          });

          // Sort by completion date descending when filtering by completion
          if (filterState.completed === true || filterState.completedAfter || filterState.completedBefore) {
            tasks.sort((a, b) => {
              const dateA = getTaskDateTimestamp(a, t => t.completionDate) || 0;
              const dateB = getTaskDateTimestamp(b, t => t.completionDate) || 0;
              return dateB - dateA;
            });
          }

          const counts = { total: 0, completed: 0, available: 0, flagged: 0 };
          tasks.forEach(t => {
            counts.total += 1;
            if (Boolean(t.completed)) { counts.completed += 1; }
            if (isTaskAvailable(t)) { counts.available += 1; }
            if (Boolean(t.flagged)) { counts.flagged += 1; }
          });

          response.data = counts;
} else if (request.op === "get_project_counts") {
          const filter = request.filter || {};
          
          // Check if this is a completion date query
          const completedAfter = filter.completedAfter ? parseFilterDate(filter.completedAfter, response.warnings) : null;
          const completedBefore = filter.completedBefore ? parseFilterDate(filter.completedBefore, response.warnings) : null;
          const completedOnly = filter.completed === true;
          
          if (completedOnly || completedAfter || completedBefore) {
            // Count completed projects by completion date
            let projects = flattenedProjects.filter(p => {
              const status = safe(() => p.status);
              // Only include completed projects (status = Done), exclude dropped
              if (status !== Project.Status.Done) return false;
              
              const completionDate = getProjectDateTimestamp(p, proj => proj.completionDate);
              if (completionDate === null) return false;
              
              if (completedAfter && completionDate < completedAfter.getTime()) return false;
              if (completedBefore && completionDate > completedBefore.getTime()) return false;
              
              return true;
            });
            
            const projectCount = projects.length;
            
            // Count completed tasks in those projects
            const projectIds = new Set(projects.map(p => String(safe(() => p.id.primaryKey) || "")));
            let completedTaskCount = 0;
            
            flattenedTasks.forEach(t => {
              const project = safe(() => t.containingProject);
              if (!project) return;
              const pid = String(safe(() => project.id.primaryKey) || "");
              if (projectIds.has(pid) && Boolean(t.completed)) {
                const taskCompletionDate = getTaskDateTimestamp(t, task => task.completionDate);
                if (taskCompletionDate !== null) {
                  // Only count tasks completed in the same window
                  if ((!completedAfter || taskCompletionDate >= completedAfter.getTime()) &&
                      (!completedBefore || taskCompletionDate < completedBefore.getTime())) {
                    completedTaskCount++;
                  }
                }
              }
            });
            
            response.data = { projects: projectCount, actions: completedTaskCount };
          } else {
            // Original behavior for non-completion queries
            const view = (typeof filter.projectView === "string") ? filter.projectView.toLowerCase() : "remaining";
            const isEverything = view === "everything";
            const isAvailableView = view === "available";

            function projectAllowed(p) {
              if (!projectMatchesView(p, view, true)) { return false; }
              if (Boolean(safe(() => p.completed))) { return false; }
              if (safe(() => p.dropDate)) { return false; }
              if (view !== "everything" && Boolean(safe(() => p.onHold))) { return false; }
              return true;
            }

            function parentAllowed(task) {
              const parent = safe(() => task.parent);
              if (!parent) { return true; }
              if (Boolean(safe(() => parent.completed))) { return false; }
              if (safe(() => parent.dropDate)) { return false; }
              return true;
            }

            let tasks = flattenedTasks;
            tasks = tasks.filter(t => {
              const project = safe(() => t.containingProject);
              return projectAllowed(project) && parentAllowed(t);
            });

            if (!isEverything) {
              tasks = tasks.filter(t => isRemainingStatus(t));
            }

            if (isAvailableView) {
              tasks = tasks.filter(t => isAvailableStatus(t));
            }

            const projectIds = new Set();
            tasks.forEach(t => {
              const project = safe(() => t.containingProject);
              if (!project) { return; }
              const pid = String(safe(() => project.id.primaryKey) || "");
              if (pid) { projectIds.add(pid); }
            });

            response.data = { projects: projectIds.size, actions: tasks.length };
          }
        } else {
          response.ok = false;
          response.error = { code: "UNKNOWN_OP", message: "Unsupported op: " + request.op };
        }
      } catch (err) {
        response.ok = false;
        response.error = { code: "BRIDGE_ERROR", message: String(err) };
      }

      response.timingMs = Date.now() - start;
      writeJSON(responsePath, response);
      removeFile(lockPath);
      removeFile(requestPath);
    };

  return lib;
})();
