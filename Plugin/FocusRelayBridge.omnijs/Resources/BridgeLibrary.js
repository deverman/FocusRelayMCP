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
      const plannedDate = hasField("plannedDate") ? safe(() => t.plannedDate) : null;
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
        plannedDate: hasField("plannedDate") && plannedDate ? plannedDate.toISOString() : null,
        deferDate: hasField("deferDate") && deferDate ? deferDate.toISOString() : null,
        completionDate: hasField("completionDate") ? (safe(() => t.completionDate) ? t.completionDate.toISOString() : null) : null,
        completed: hasField("completed") ? isCompletedStatus(t) : null,
        flagged: hasField("flagged") ? Boolean(t.flagged) : null,
        estimatedMinutes: hasField("estimatedMinutes") ? t.estimatedMinutes : null,
        available: hasField("available") ? isTaskAvailable(t) : null
      };
    }

    function normalizeIdentifierArray(values) {
      if (!Array.isArray(values)) { return []; }
      return values
        .map(value => String(value))
        .filter(value => value.length > 0);
    }

    function validateTaskPatch(taskPatch) {
      if (!taskPatch) { return "update_tasks requires a taskPatch payload."; }
      if (taskPatch.dueDate && taskPatch.clearDueDate) {
        return "Task patches cannot set and clear dueDate in the same request.";
      }
      if (taskPatch.deferDate && taskPatch.clearDeferDate) {
        return "Task patches cannot set and clear deferDate in the same request.";
      }
      if (taskPatch.estimatedMinutes !== undefined && taskPatch.estimatedMinutes !== null && Number(taskPatch.estimatedMinutes) < 0) {
        return "estimatedMinutes must be zero or greater.";
      }

      const tags = taskPatch.tags;
      if (!tags) { return null; }

      const add = normalizeIdentifierArray(tags.add);
      const remove = normalizeIdentifierArray(tags.remove);
      const set = normalizeIdentifierArray(tags.set);
      const clear = Boolean(tags.clear);

      if (set.length > 0 && (add.length > 0 || remove.length > 0 || clear)) {
        return "Tag set operations cannot be combined with add, remove, or clear.";
      }
      if (clear && (add.length > 0 || remove.length > 0)) {
        return "Tag clear operations cannot be combined with add or remove.";
      }
      if (set.length === 0 && add.length === 0 && remove.length === 0 && !clear) {
        return "Tag operations must include add, remove, set, or clear.";
      }
      if (new Set(add).size !== add.length) {
        return "Tag add operations must not contain duplicate tag IDs.";
      }
      if (new Set(remove).size !== remove.length) {
        return "Tag remove operations must not contain duplicate tag IDs.";
      }
      if (new Set(set).size !== set.length) {
        return "Tag set operations must not contain duplicate tag IDs.";
      }

      const overlaps = add.filter(id => remove.indexOf(id) !== -1);
      if (overlaps.length > 0) {
        return "Tag add and remove operations must not reference the same tag IDs.";
      }

      return null;
    }

    function resolveTaskPatchTags(taskPatch) {
      if (!taskPatch || !taskPatch.tags) { return { ok: true, tags: null }; }

      const allTags = toTaskArray(safe(() => flattenedTags));
      const tagsByID = {};
      allTags.forEach(tag => {
        const id = String(safe(() => tag.id.primaryKey) || "");
        if (id.length > 0) {
          tagsByID[id] = tag;
        }
      });

      function resolve(ids) {
        const resolved = [];
        const missing = [];
        ids.forEach(id => {
          const tag = tagsByID[id];
          if (tag) {
            resolved.push(tag);
          } else {
            missing.push(id);
          }
        });
        return { resolved, missing };
      }

      const addIDs = normalizeIdentifierArray(taskPatch.tags.add);
      const removeIDs = normalizeIdentifierArray(taskPatch.tags.remove);
      const setIDs = normalizeIdentifierArray(taskPatch.tags.set);
      const clear = Boolean(taskPatch.tags.clear);

      const add = resolve(addIDs);
      const remove = resolve(removeIDs);
      const set = resolve(setIDs);
      const missing = add.missing.concat(remove.missing, set.missing);

      if (missing.length > 0) {
        return {
          ok: false,
          message: "Unknown tag IDs: " + Array.from(new Set(missing)).join(", ")
        };
      }

      return {
        ok: true,
        tags: {
          clear: clear,
          add: add.resolved,
          addIDs: addIDs,
          remove: remove.resolved,
          removeIDs: removeIDs,
          set: set.resolved,
          setIDs: setIDs
        }
      };
    }

    function taskReturnedFields(task, returnFields) {
      const fields = normalizeIdentifierArray(returnFields);
      if (fields.length === 0) { return null; }
      return taskToPayload(task, fields);
    }

    function validateCompletionMutation(completion) {
      if (!completion || !completion.state) {
        return "set_tasks_completion requires a completion payload.";
      }
      if (completion.state !== "active" && completion.state !== "completed") {
        return "Completion state must be either active or completed.";
      }
      return null;
    }

    function currentTaskTagIDs(task) {
      return (safe(() => task.tags) || []).map(tag => String(safe(() => tag.id.primaryKey) || "")).filter(Boolean);
    }

    function compareISODate(taskDate, mutationDate) {
      if (!taskDate && !mutationDate) { return true; }
      if (!taskDate || !mutationDate) { return false; }
      try {
        return taskDate.toISOString() === new Date(mutationDate).toISOString();
      } catch (e) {
        return false;
      }
    }

    function applyTaskPatch(task, taskPatch, resolvedTags) {
      if (taskPatch.name !== undefined && taskPatch.name !== null) {
        task.name = taskPatch.name;
      }
      if (taskPatch.note !== undefined && taskPatch.note !== null) {
        task.note = taskPatch.note;
      }
      if (taskPatch.noteAppend !== undefined && taskPatch.noteAppend !== null) {
        task.appendStringToNote(taskPatch.noteAppend);
      }
      if (taskPatch.flagged !== undefined && taskPatch.flagged !== null) {
        task.flagged = Boolean(taskPatch.flagged);
      }
      if (taskPatch.estimatedMinutes !== undefined && taskPatch.estimatedMinutes !== null) {
        task.estimatedMinutes = Number(taskPatch.estimatedMinutes);
      }
      if (taskPatch.clearDueDate) {
        task.dueDate = null;
      } else if (taskPatch.dueDate) {
        task.dueDate = new Date(taskPatch.dueDate);
      }
      if (taskPatch.clearDeferDate) {
        task.deferDate = null;
      } else if (taskPatch.deferDate) {
        task.deferDate = new Date(taskPatch.deferDate);
      }

      if (!resolvedTags) { return; }

      if (resolvedTags.setIDs.length > 0) {
        task.clearTags();
        if (resolvedTags.set.length === 1) {
          task.addTag(resolvedTags.set[0]);
        } else if (resolvedTags.set.length > 1) {
          task.addTags(resolvedTags.set);
        }
        return;
      }

      if (resolvedTags.clear) {
        task.clearTags();
      }
      if (resolvedTags.remove.length === 1) {
        task.removeTag(resolvedTags.remove[0]);
      } else if (resolvedTags.remove.length > 1) {
        task.removeTags(resolvedTags.remove);
      }
      if (resolvedTags.add.length === 1) {
        task.addTag(resolvedTags.add[0]);
      } else if (resolvedTags.add.length > 1) {
        task.addTags(resolvedTags.add);
      }
    }

    function verifyTaskPatch(task, taskPatch, resolvedTags) {
      if (taskPatch.name !== undefined && taskPatch.name !== null) {
        if (String(safe(() => task.name) || "") !== String(taskPatch.name)) {
          return "name did not match requested value.";
        }
      }

      const currentNote = String(safe(() => task.note) || "");
      if (taskPatch.note !== undefined && taskPatch.note !== null && taskPatch.noteAppend !== undefined && taskPatch.noteAppend !== null) {
        if (currentNote !== String(taskPatch.note) + String(taskPatch.noteAppend)) {
          return "note did not match requested replacement plus append.";
        }
      } else if (taskPatch.note !== undefined && taskPatch.note !== null) {
        if (currentNote !== String(taskPatch.note)) {
          return "note did not match requested replacement.";
        }
      } else if (taskPatch.noteAppend !== undefined && taskPatch.noteAppend !== null) {
        if (!currentNote.endsWith(String(taskPatch.noteAppend))) {
          return "note did not end with requested appended text.";
        }
      }

      if (taskPatch.flagged !== undefined && taskPatch.flagged !== null) {
        if (Boolean(safe(() => task.flagged)) !== Boolean(taskPatch.flagged)) {
          return "flagged did not match requested value.";
        }
      }

      if (taskPatch.estimatedMinutes !== undefined && taskPatch.estimatedMinutes !== null) {
        if (Number(safe(() => task.estimatedMinutes)) !== Number(taskPatch.estimatedMinutes)) {
          return "estimatedMinutes did not match requested value.";
        }
      }

      if (taskPatch.clearDueDate) {
        if (safe(() => task.dueDate) !== null) {
          return "dueDate was not cleared.";
        }
      } else if (taskPatch.dueDate && !compareISODate(safe(() => task.dueDate), taskPatch.dueDate)) {
        return "dueDate did not match requested value.";
      }

      if (taskPatch.clearDeferDate) {
        if (safe(() => task.deferDate) !== null) {
          return "deferDate was not cleared.";
        }
      } else if (taskPatch.deferDate && !compareISODate(safe(() => task.deferDate), taskPatch.deferDate)) {
        return "deferDate did not match requested value.";
      }

      if (!resolvedTags) { return null; }

      const currentIDs = currentTaskTagIDs(task);
      const currentSet = new Set(currentIDs);
      if (resolvedTags.setIDs.length > 0) {
        if (currentIDs.length !== resolvedTags.setIDs.length) {
          return "tag set size did not match requested value.";
        }
        const allPresent = resolvedTags.setIDs.every(id => currentSet.has(id));
        return allPresent ? null : "tag set did not match requested value.";
      }
      if (resolvedTags.clear && currentIDs.length !== 0) {
        return "tags were not cleared.";
      }
      const missingAdded = resolvedTags.addIDs.find(id => !currentSet.has(id));
      if (missingAdded) {
        return "tag add did not include requested tag ID " + missingAdded + ".";
      }
      const removedStillPresent = resolvedTags.removeIDs.find(id => currentSet.has(id));
      if (removedStillPresent) {
        return "tag remove did not remove requested tag ID " + removedStillPresent + ".";
      }

      return null;
    }

    function verifyTaskCompletion(task, completedTask, requestedState) {
      if (requestedState === "completed") {
        if (completedTask && String(safe(() => completedTask.id.primaryKey) || "") !== String(safe(() => task.id.primaryKey) || "")) {
          if (!isCompletedStatus(completedTask)) {
            return "repeating task completion did not produce a completed occurrence.";
          }
          if (isCompletedStatus(task)) {
            return "repeating task source should remain active after completion.";
          }
          return null;
        }
        if (!isCompletedStatus(task)) {
          return "task did not reach completed state.";
        }
        return null;
      }

      if (isCompletedStatus(task)) {
        return "task did not return to active state.";
      }
      return null;
    }

    function completionResultFields(task, completedTask, requestedState, returnFields) {
      if (requestedState === "completed" && completedTask) {
        const completedID = String(safe(() => completedTask.id.primaryKey) || "");
        const taskID = String(safe(() => task.id.primaryKey) || "");
        if (completedID.length > 0 && completedID !== taskID) {
          return taskReturnedFields(completedTask, returnFields);
        }
      }
      return taskReturnedFields(task, returnFields);
    }

    function destinationLabel(move, projectByID, taskByID) {
      if (move.destinationKind === "inbox") {
        return "inbox";
      }
      if (move.destinationKind === "project") {
        const project = projectByID[move.destinationID];
        const name = String(safe(() => project.name) || move.destinationID);
        return "project " + name;
      }
      if (move.destinationKind === "parent_task") {
        const task = taskByID[move.destinationID];
        const name = String(safe(() => task.name) || move.destinationID);
        return "parent task " + name;
      }
      return String(move.destinationKind);
    }

    function buildMoveDestination(move, projectByID, taskByID) {
      const position = String(move.position || "ending").toLowerCase();
      if (move.destinationKind === "inbox") {
        return {
          ok: true,
          location: position === "beginning" ? inbox.beginning : inbox.ending,
          label: "inbox"
        };
      }
      if (move.destinationKind === "project") {
        const project = projectByID[move.destinationID];
        if (!project) {
          return { ok: false, message: "Destination project ID not found." };
        }
        return {
          ok: true,
          location: position === "beginning" ? project.beginning : project.ending,
          label: "project " + String(safe(() => project.name) || move.destinationID)
        };
      }
      if (move.destinationKind === "parent_task") {
        const parentTask = taskByID[move.destinationID];
        if (!parentTask) {
          return { ok: false, message: "Destination parent task ID not found." };
        }
        return {
          ok: true,
          location: position === "beginning" ? parentTask.beginning : parentTask.ending,
          parentTask: parentTask,
          label: "parent task " + String(safe(() => parentTask.name) || move.destinationID)
        };
      }
      return { ok: false, message: "Unsupported move destination kind " + String(move.destinationKind) + "." };
    }

    function validateMoveMutation(move, targetIDs, projectByID, taskByID) {
      if (!move || !move.destinationKind) {
        return "move_tasks requires a move payload.";
      }

      const position = String(move.position || "ending").toLowerCase();
      if (position !== "beginning" && position !== "ending") {
        return "Move position must be beginning or ending.";
      }

      if (move.destinationKind === "inbox") {
        if (move.destinationID !== undefined && move.destinationID !== null) {
          return "Inbox moves must not include a destinationID.";
        }
        return null;
      }

      if (!move.destinationID) {
        return "Move destination requires a destinationID.";
      }

      if (move.destinationKind === "project") {
        return projectByID[move.destinationID] ? null : "Destination project ID not found.";
      }

      if (move.destinationKind === "parent_task") {
        const parentTask = taskByID[move.destinationID];
        if (!parentTask) {
          return "Destination parent task ID not found.";
        }
        for (let i = 0; i < targetIDs.length; i += 1) {
          const task = taskByID[targetIDs[i]];
          if (!task) { continue; }
          const taskID = String(safe(() => task.id.primaryKey) || "");
          const parentID = String(safe(() => parentTask.id.primaryKey) || "");
          if (taskID === parentID) {
            return "Tasks cannot be moved under themselves.";
          }
          const descendantIDs = new Set(toTaskArray(safe(() => task.flattenedTasks)).map(item => String(safe(() => item.id.primaryKey) || "")));
          if (descendantIDs.has(parentID)) {
            return "Tasks cannot be moved under one of their descendants.";
          }
        }
        return null;
      }

      return "Unsupported move destination kind " + String(move.destinationKind) + ".";
    }

    function verifyTaskMove(task, move, destination, projectByID, taskByID) {
      const project = safe(() => task.containingProject);
      const parent = safe(() => task.parent);
      const projectID = String(safe(() => project.id.primaryKey) || "");
      const parentID = String(safe(() => parent.id.primaryKey) || "");

      if (move.destinationKind === "inbox") {
        if (!Boolean(safe(() => task.inInbox))) {
          return "task did not return to inbox.";
        }
        return null;
      }

      if (move.destinationKind === "project") {
        const destinationID = String(move.destinationID || "");
        if (projectID !== destinationID) {
          return "task project did not match the requested destination.";
        }
        return null;
      }

      if (move.destinationKind === "parent_task") {
        const destinationID = String(move.destinationID || "");
        if (parentID !== destinationID) {
          return "task parent did not match the requested destination.";
        }
        return null;
      }

      return "Unsupported move destination kind " + String(move.destinationKind) + ".";
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

    function isCompletedStatusValue(st) {
      if (st === Task.Status.Completed) { return true; }
      return String(st).includes("Completed");
    }

    function isCompletedStatus(task) {
      return isCompletedStatusValue(taskStatus(task));
    }

    function isDroppedStatusValue(st) {
      if (st === Task.Status.Dropped) { return true; }
      return String(st).includes("Dropped");
    }

    function isDroppedStatus(task) {
      return isDroppedStatusValue(taskStatus(task));
    }

    /**
     * Check if task is remaining (not completed or dropped)
     * @param {Task} task - OmniFocus task object  
     * @returns {boolean} True if task is remaining
     */
    function isRemainingStatus(task) {
      const st = taskStatus(task);
      return !isCompletedStatusValue(st) && !isDroppedStatusValue(st);
    }

    /**
     * Check if task status indicates availability
     * Note: This checks ONLY the task status, not project/parent status
     * @param {Task} task - OmniFocus task object
     * @returns {boolean} True if task has an available status
     */
    function isAvailableStatusValue(st) {
      return st === Task.Status.Available ||
        st === Task.Status.DueSoon ||
        st === Task.Status.Next ||
        st === Task.Status.Overdue;
    }

    function isAvailableStatus(task) {
      return isAvailableStatusValue(taskStatus(task));
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
      if (normalizedView === "everything") { return true; }
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
    function isTaskAvailableWithStatus(task, taskStatusValue, knownProject) {
      const project = knownProject === undefined ? safe(() => task.containingProject) : knownProject;
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
      }

      const parent = safe(() => task.parent);
      if (parent) {
        if (isCompletedStatus(parent)) { return false; }
        if (isDroppedStatus(parent)) { return false; }
      }

      return isAvailableStatusValue(taskStatusValue);
    }

    function isTaskAvailable(task) {
      return isTaskAvailableWithStatus(task, taskStatus(task), undefined);
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

    // Normalize OmniFocus collections to plain arrays.
    function toTaskArray(collection) {
      if (!collection) { return []; }
      if (Array.isArray(collection)) { return collection; }
      if (typeof collection.apply === "function") {
        const tasks = [];
        collection.apply(task => tasks.push(task));
        return tasks;
      }
      try {
        return Array.from(collection);
      } catch (e) {
        return [];
      }
    }

    function inboxTasksArray() {
      const tasks = [];
      inbox.apply(task => tasks.push(task));
      return tasks;
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
        } else if (request.op === "perform_mutation") {
          const mutation = request.mutation || {};
          const targetType = mutation.targetType;
          const ids = normalizeIdentifierArray(mutation.targetIDs);
          const operation = mutation.operation || {};

          if (operation.kind === "update_tasks") {
            const patchError = validateTaskPatch(operation.taskPatch);
            if (patchError) {
              const results = ids.map(id => ({
                id: id,
                status: "failed",
                message: patchError
              }));
              response.data = {
                targetType: targetType,
                operationKind: operation.kind,
                previewOnly: Boolean(mutation.previewOnly),
                verify: Boolean(mutation.verify),
                requestedCount: ids.length,
                successCount: 0,
                failureCount: results.length,
                results: results,
                warnings: []
              };
            } else {
              const resolvedTags = resolveTaskPatchTags(operation.taskPatch);
              if (!resolvedTags.ok) {
                const results = ids.map(id => ({
                  id: id,
                  status: "failed",
                  message: resolvedTags.message
                }));
                response.data = {
                  targetType: targetType,
                  operationKind: operation.kind,
                  previewOnly: Boolean(mutation.previewOnly),
                  verify: Boolean(mutation.verify),
                  requestedCount: ids.length,
                  successCount: 0,
                  failureCount: results.length,
                  results: results,
                  warnings: []
                };
              } else {
                const pool = toTaskArray(safe(() => flattenedTasks));
                const tasksByID = {};
                pool.forEach(task => {
                  const id = String(safe(() => task.id.primaryKey) || "");
                  if (id.length > 0) {
                    tasksByID[id] = task;
                  }
                });

                const results = [];
                let successCount = 0;
                let mutatedAny = false;

                ids.forEach(id => {
                  const task = tasksByID[id];
                  if (!task) {
                    results.push({
                      id: id,
                      status: "failed",
                      message: "Target ID not found."
                    });
                    return;
                  }

                  if (mutation.previewOnly) {
                    results.push({
                      id: id,
                      status: "previewed",
                      message: "Validated target and shared patch for preview."
                    });
                    successCount += 1;
                    return;
                  }

                  applyTaskPatch(task, operation.taskPatch, resolvedTags.tags);
                  mutatedAny = true;

                  if (mutation.verify) {
                    const verificationError = verifyTaskPatch(task, operation.taskPatch, resolvedTags.tags);
                    if (verificationError) {
                      results.push({
                        id: id,
                        status: "failed",
                        message: "Mutation applied but verification failed: " + verificationError,
                        returnedFields: taskReturnedFields(task, mutation.returnFields)
                      });
                      return;
                    }
                  }

                  results.push({
                    id: id,
                    status: "mutated",
                    message: mutation.verify ? "Task updated and verified." : "Task updated.",
                    returnedFields: taskReturnedFields(task, mutation.returnFields)
                  });
                  successCount += 1;
                });

                if (mutatedAny) {
                  safe(() => save());
                }

                response.data = {
                  targetType: targetType,
                  operationKind: operation.kind,
                  previewOnly: Boolean(mutation.previewOnly),
                  verify: Boolean(mutation.verify),
                  requestedCount: ids.length,
                  successCount: successCount,
                  failureCount: results.length - successCount,
                  results: results,
                  warnings: []
                };
              }
            }
          } else if (operation.kind === "set_tasks_completion") {
            const completionError = validateCompletionMutation(operation.completion);
            if (completionError) {
              const results = ids.map(id => ({
                id: id,
                status: "failed",
                message: completionError
              }));
              response.data = {
                targetType: targetType,
                operationKind: operation.kind,
                previewOnly: Boolean(mutation.previewOnly),
                verify: Boolean(mutation.verify),
                requestedCount: ids.length,
                successCount: 0,
                failureCount: results.length,
                results: results,
                warnings: []
              };
            } else {
              const requestedState = operation.completion.state;
              const pool = toTaskArray(safe(() => flattenedTasks));
              const tasksByID = {};
              pool.forEach(task => {
                const id = String(safe(() => task.id.primaryKey) || "");
                if (id.length > 0) {
                  tasksByID[id] = task;
                }
              });

              const results = [];
              let successCount = 0;
              let mutatedAny = false;

              ids.forEach(id => {
                const task = tasksByID[id];
                if (!task) {
                  results.push({
                    id: id,
                    status: "failed",
                    message: "Target ID not found."
                  });
                  return;
                }

                const isRepeating = Boolean(safe(() => task.repetitionRule));
                if (mutation.previewOnly) {
                  results.push({
                    id: id,
                    status: "previewed",
                    message: requestedState === "completed" && isRepeating
                      ? "Validated repeating task target for completion preview."
                      : "Validated target for completion preview."
                  });
                  successCount += 1;
                  return;
                }

                let completedTask = null;
                if (requestedState === "completed") {
                  completedTask = task.markComplete(null);
                } else {
                  task.markIncomplete();
                }
                mutatedAny = true;

                if (mutation.verify) {
                  const verificationError = verifyTaskCompletion(task, completedTask, requestedState);
                  if (verificationError) {
                    results.push({
                      id: id,
                      status: "failed",
                      message: "Mutation applied but verification failed: " + verificationError,
                      returnedFields: completionResultFields(task, completedTask, requestedState, mutation.returnFields)
                    });
                    return;
                  }
                }

                let message = requestedState === "completed" ? "Task completed." : "Task marked active.";
                if (requestedState === "completed" && completedTask) {
                  const completedID = String(safe(() => completedTask.id.primaryKey) || "");
                  const taskID = String(safe(() => task.id.primaryKey) || "");
                  if (completedID.length > 0 && completedID !== taskID) {
                    message = "Repeating task completed and advanced to the next occurrence."
                  }
                }
                if (mutation.verify) {
                  message = message.replace(/\.$/, "") + " Verified.";
                }

                results.push({
                  id: id,
                  status: "mutated",
                  message: message,
                  returnedFields: completionResultFields(task, completedTask, requestedState, mutation.returnFields)
                });
                successCount += 1;
              });

              if (mutatedAny) {
                safe(() => save());
              }

              response.data = {
                targetType: targetType,
                operationKind: operation.kind,
                previewOnly: Boolean(mutation.previewOnly),
                verify: Boolean(mutation.verify),
                requestedCount: ids.length,
                successCount: successCount,
                failureCount: results.length - successCount,
                results: results,
                warnings: []
              };
            }
          } else if (operation.kind === "move_tasks") {
            const projects = toTaskArray(safe(() => flattenedProjects));
            const tasks = toTaskArray(safe(() => flattenedTasks));
            const projectByID = {};
            const taskByID = {};
            projects.forEach(project => {
              const id = String(safe(() => project.id.primaryKey) || "");
              if (id.length > 0) { projectByID[id] = project; }
            });
            tasks.forEach(task => {
              const id = String(safe(() => task.id.primaryKey) || "");
              if (id.length > 0) { taskByID[id] = task; }
            });

            const moveError = validateMoveMutation(operation.move, ids, projectByID, taskByID);
            if (moveError) {
              const results = ids.map(id => ({
                id: id,
                status: "failed",
                message: moveError
              }));
              response.data = {
                targetType: targetType,
                operationKind: operation.kind,
                previewOnly: Boolean(mutation.previewOnly),
                verify: Boolean(mutation.verify),
                requestedCount: ids.length,
                successCount: 0,
                failureCount: results.length,
                results: results,
                warnings: []
              };
            } else {
              const destination = buildMoveDestination(operation.move, projectByID, taskByID);
              if (!destination.ok) {
                const results = ids.map(id => ({
                  id: id,
                  status: "failed",
                  message: destination.message
                }));
                response.data = {
                  targetType: targetType,
                  operationKind: operation.kind,
                  previewOnly: Boolean(mutation.previewOnly),
                  verify: Boolean(mutation.verify),
                  requestedCount: ids.length,
                  successCount: 0,
                  failureCount: results.length,
                  results: results,
                  warnings: []
                };
              } else {
                const results = [];
                let successCount = 0;
                let mutatedAny = false;

                ids.forEach(id => {
                  const task = taskByID[id];
                  if (!task) {
                    results.push({
                      id: id,
                      status: "failed",
                      message: "Target ID not found."
                    });
                    return;
                  }

                  if (mutation.previewOnly) {
                    results.push({
                      id: id,
                      status: "previewed",
                      message: "Validated move target and destination " + destination.label + " for preview."
                    });
                    successCount += 1;
                    return;
                  }

                  moveTasks([task], destination.location);
                  mutatedAny = true;

                  if (mutation.verify) {
                    const verificationError = verifyTaskMove(task, operation.move, destination, projectByID, taskByID);
                    if (verificationError) {
                      results.push({
                        id: id,
                        status: "failed",
                        message: "Mutation applied but verification failed: " + verificationError,
                        returnedFields: taskReturnedFields(task, mutation.returnFields)
                      });
                      return;
                    }
                  }

                  let message = "Task moved to " + destination.label + ".";
                  if (mutation.verify) {
                    message = message.replace(/\.$/, "") + " Verified.";
                  }

                  results.push({
                    id: id,
                    status: "mutated",
                    message: message,
                    returnedFields: taskReturnedFields(task, mutation.returnFields)
                  });
                  successCount += 1;
                });

                if (mutatedAny) {
                  safe(() => save());
                }

                response.data = {
                  targetType: targetType,
                  operationKind: operation.kind,
                  previewOnly: Boolean(mutation.previewOnly),
                  verify: Boolean(mutation.verify),
                  requestedCount: ids.length,
                  successCount: successCount,
                  failureCount: results.length - successCount,
                  results: results,
                  warnings: []
                };
              }
            }
          } else {
            if (!mutation.previewOnly) {
              throw new Error("Mutation execution is not implemented yet for " + String(operation.kind) + ". Use previewOnly=true.");
            }

            const pool = targetType === "project" ? toTaskArray(safe(() => flattenedProjects)) : toTaskArray(safe(() => flattenedTasks));
            const knownIDs = {};

            for (let i = 0; i < pool.length; i += 1) {
              const item = pool[i];
              const id = String(safe(() => item.id.primaryKey) || "");
              if (id.length > 0) {
                knownIDs[id] = true;
              }
            }

            const results = ids.map(id => {
              const normalized = String(id);
              if (knownIDs[normalized]) {
                return {
                  id: normalized,
                  status: "previewed",
                  message: "Validated target for preview."
                };
              }
              return {
                id: normalized,
                status: "failed",
                message: "Target ID not found."
              };
            });

            const successCount = results.filter(item => item.status === "previewed").length;
            const failureCount = results.length - successCount;
            response.data = {
              targetType: targetType,
              operationKind: operation.kind,
              previewOnly: true,
              verify: Boolean(mutation.verify),
              requestedCount: ids.length,
              successCount: successCount,
              failureCount: failureCount,
              results: results,
              warnings: []
            };
          }
        } else if (request.op === "list_inbox" || request.op === "list_tasks") {
          const filter = request.filter || {};
          const debugListTasks = filter.search === "__debug_list_tasks__";
          const listTasksDebug = debugListTasks ? {
            requestId: requestId,
            op: request.op,
            marks: []
          } : null;
          const markListTasks = (label, extra) => {
            if (!listTasksDebug) { return; }
            const entry = Object.assign({ label: label, ms: Date.now() - start }, extra || {});
            listTasksDebug.marks.push(entry);
          };
          const fields = request.fields || [];
          const hasField = (name) => fields.length === 0 || fields.indexOf(name) !== -1;

          let tasks = [];
          const useInbox = filter.inboxOnly === true || request.op === "list_inbox";
          if (useInbox) {
            inbox.apply(task => tasks.push(task));
          } else {
            tasks = flattenedTasks;
          }
          markListTasks("selected_base_pool", { useInbox: useInbox, count: tasks.length });

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
          markListTasks("after_project_scope", { count: tasks.length, projectFilter: filter.project || null });
          // Note: When inboxOnly is false and no project filter is specified,
          // we return tasks from all projects (flattenedTasks)

          const inboxView = (typeof filter.inboxView === "string") ? filter.inboxView.toLowerCase() : "available";
          const isEverything = inboxView === "everything";
          const isRemaining = inboxView === "remaining";

          const availableOnly = (typeof filter.availableOnly === "boolean")
            ? filter.availableOnly
            : (filter.completed === true ? false : !isRemaining && !isEverything);
          markListTasks("derived_view_state", {
            count: tasks.length,
            completed: filter.completed,
            inboxView: inboxView,
            availableOnly: availableOnly
          });

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
            availableOnly: availableOnly,
            
            // Project filter
            projectFilter: filter.project,
            
            // Date filters (pre-parsed)
            dueBeforeTs: filter.dueBefore ? safe(() => parseFilterDate(filter.dueBefore, response.warnings).getTime()) : null,
            dueAfterTs: filter.dueAfter ? safe(() => parseFilterDate(filter.dueAfter, response.warnings).getTime()) : null,
            plannedBeforeTs: filter.plannedBefore ? safe(() => parseFilterDate(filter.plannedBefore, response.warnings).getTime()) : null,
            plannedAfterTs: filter.plannedAfter ? safe(() => parseFilterDate(filter.plannedAfter, response.warnings).getTime()) : null,
            deferBeforeTs: filter.deferBefore ? safe(() => parseFilterDate(filter.deferBefore, response.warnings).getTime()) : null,
            deferAfterTs: filter.deferAfter ? safe(() => parseFilterDate(filter.deferAfter, response.warnings).getTime()) : null,
            completedBeforeTs: filter.completedBefore ? safe(() => parseFilterDate(filter.completedBefore, response.warnings).getTime()) : null,
            completedAfterTs: filter.completedAfter ? safe(() => parseFilterDate(filter.completedAfter, response.warnings).getTime()) : null,
            
            // Duration filters
            maxEstimatedMinutes: filter.maxEstimatedMinutes,
            minEstimatedMinutes: filter.minEstimatedMinutes,
            
            // Tag filters
            tags: Array.isArray(filter.tags) ? filter.tags : null,
            untaggedOnly: Array.isArray(filter.tags) && filter.tags.length === 0
          };
          
          const projectView = (typeof filter.projectView === "string") ? filter.projectView.toLowerCase() : null;

          // Helper function to check if a task matches all filters
          function taskMatchesFilters(t, knownTaskStatus, knownProject, knownCompletionTs) {
            const taskStatusValue = knownTaskStatus === undefined ? taskStatus(t) : knownTaskStatus;
            // Status checks
            if (filterState.completed !== undefined) {
              const taskCompleted = isCompletedStatusValue(taskStatusValue);
              if (taskCompleted !== filterState.completed) return false;
            } else if (!isEverything) {
              if (isCompletedStatusValue(taskStatusValue) || isDroppedStatusValue(taskStatusValue)) return false;
            }
            if (filterState.flagged !== undefined) {
              const taskFlagged = Boolean(t.flagged);
              if (taskFlagged !== filterState.flagged) return false;
            }
            let project = knownProject === undefined ? null : knownProject;
            if (filterState.availableOnly) {
              if (!isTaskAvailableWithStatus(t, taskStatusValue, project === null ? undefined : project)) return false;
            }
            
            // Project check
            if (filterState.projectFilter) {
              if (project === null) {
                project = safe(() => t.containingProject);
              }
              if (!project) return false;
              const pid = String(safe(() => project.id.primaryKey) || "");
              const pname = String(safe(() => project.name) || "");
              if (pid !== filterState.projectFilter && pname !== filterState.projectFilter) return false;
            }
            if (projectView) {
              if (project === null) {
                project = safe(() => t.containingProject);
              }
              if (!projectMatchesView(project, projectView, true)) return false;
            }
            
            // Date checks
            if (filterState.dueBeforeTs !== null) {
              const due = getTaskDateTimestamp(t, task => task.dueDate);
              if (due === null || due > filterState.dueBeforeTs) return false;
            }
            if (filterState.dueAfterTs !== null) {
              const due = getTaskDateTimestamp(t, task => task.dueDate);
              if (due === null || due < filterState.dueAfterTs) return false;
            }
            if (filterState.deferBeforeTs !== null) {
              const defer = getTaskDateTimestamp(t, task => task.deferDate);
              if (defer === null || defer > filterState.deferBeforeTs) return false;
            }
            if (filterState.deferAfterTs !== null) {
              const defer = getTaskDateTimestamp(t, task => task.deferDate);
              if (defer === null || defer < filterState.deferAfterTs) return false;
            }
            if (filterState.plannedBeforeTs !== null) {
              const planned = getTaskDateTimestamp(t, task => task.plannedDate);
              if (planned === null || planned > filterState.plannedBeforeTs) return false;
            }
            if (filterState.plannedAfterTs !== null) {
              const planned = getTaskDateTimestamp(t, task => task.plannedDate);
              if (planned === null || planned < filterState.plannedAfterTs) return false;
            }
            
            // Completion date checks
            if (filterState.completedBeforeTs !== null) {
              const completed = knownCompletionTs === undefined ? getTaskDateTimestamp(t, task => task.completionDate) : knownCompletionTs;
              if (completed === null || completed > filterState.completedBeforeTs) return false;
            }
            if (filterState.completedAfterTs !== null) {
              const completed = knownCompletionTs === undefined ? getTaskDateTimestamp(t, task => task.completionDate) : knownCompletionTs;
              if (completed === null || completed < filterState.completedAfterTs) return false;
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
          
          const includeTotalCount = filter.includeTotalCount === true;
          const limit = request.page && request.page.limit ? request.page.limit : 50;
          const offset = request.page && request.page.cursor ? parseInt(request.page.cursor, 10) : 0;
          const safeOffset = Number.isFinite(offset) && offset > 0 ? offset : 0;
          const requiresCompletionSort = filterState.completed === true || filterState.completedAfterTs !== null || filterState.completedBeforeTs !== null;
          const hasScheduleFilters =
            filterState.dueBeforeTs !== null ||
            filterState.dueAfterTs !== null ||
            filterState.deferBeforeTs !== null ||
            filterState.deferAfterTs !== null ||
            filterState.plannedBeforeTs !== null ||
            filterState.plannedAfterTs !== null;
          const hasAdvancedFilters =
            Boolean(filterState.projectFilter) ||
            Boolean(projectView) ||
            hasScheduleFilters ||
            filterState.maxEstimatedMinutes !== undefined ||
            filterState.minEstimatedMinutes !== undefined ||
            Boolean(filterState.tags) ||
            Boolean(filter.search);
          const useStreamedSimplePath =
            !requiresCompletionSort &&
            filterState.availableOnly &&
            !hasAdvancedFilters;
          const useCompletionTopKPath = requiresCompletionSort;

          if (useStreamedSimplePath) {
            const fastPathStart = Date.now();
            const pageTasks = [];
            let matchedCount = 0;
            let afterStatusGateCount = 0;
            let afterAvailableGateCount = 0;
            let hasMore = false;

            for (let i = 0; i < tasks.length; i += 1) {
              const t = tasks[i];
              const taskStatusValue = taskStatus(t);
              if (isCompletedStatusValue(taskStatusValue) || isDroppedStatusValue(taskStatusValue)) {
                continue;
              }
              afterStatusGateCount += 1;

              if (filterState.flagged !== undefined) {
                const taskFlagged = Boolean(t.flagged);
                if (taskFlagged !== filterState.flagged) {
                  continue;
                }
              }

              if (!isAvailableStatusValue(taskStatusValue)) {
                continue;
              }
              if (!isTaskAvailableWithStatus(t, taskStatusValue, undefined)) {
                continue;
              }

              afterAvailableGateCount += 1;

              if (matchedCount < safeOffset) {
                matchedCount += 1;
                continue;
              }
              if (pageTasks.length < limit) {
                pageTasks.push(t);
                matchedCount += 1;
                continue;
              }

              if (!includeTotalCount) {
                hasMore = true;
                break;
              }

              matchedCount += 1;
            }

            const totalCount = includeTotalCount ? matchedCount : null;
            if (includeTotalCount) {
              hasMore = (safeOffset + pageTasks.length) < matchedCount;
            }

            markListTasks("after_stream_fast_path", {
              returnedCount: pageTasks.length,
              scannedCount: tasks.length,
              matchedCount: matchedCount,
              afterStatusGateCount: afterStatusGateCount,
              afterAvailableGateCount: afterAvailableGateCount,
              durationMs: Date.now() - fastPathStart,
              offset: safeOffset,
              limit: limit,
              hasMore: hasMore,
              includeTotalCount: includeTotalCount,
              totalCount: totalCount
            });

            const payloadStart = Date.now();
            const items = pageTasks.map(t => taskToPayload(t, fields));
            markListTasks("after_payload_map", {
              returnedCount: items.length,
              durationMs: Date.now() - payloadStart
            });

            const returnedCount = items.length;
            const nextCursor = hasMore ? String(safeOffset + items.length) : null;
            response.data = { items: items, nextCursor: nextCursor, returnedCount: returnedCount };
            if (includeTotalCount) {
              response.data.totalCount = totalCount;
            }
            if (listTasksDebug) {
              listTasksDebug.totalTimingMs = Date.now() - start;
              try {
                writeJSON(basePath + "/logs/list_tasks_debug_" + requestId + ".json", listTasksDebug);
              } catch (debugError) {}
            }
          } else if (useCompletionTopKPath) {
            const completionPathStart = Date.now();
            const windowSize = Math.max(limit + 1, safeOffset + limit + 1);
            const rankedEntries = [];
            let matchedCount = 0;

            function compareCompletionEntries(a, b) {
              if (a.sortCompletionTs !== b.sortCompletionTs) {
                return b.sortCompletionTs - a.sortCompletionTs;
              }
              return a.scanIndex - b.scanIndex;
            }

            function insertCompletionEntry(entry) {
              let insertAt = rankedEntries.length;
              while (insertAt > 0 && compareCompletionEntries(entry, rankedEntries[insertAt - 1]) < 0) {
                insertAt -= 1;
              }
              rankedEntries.splice(insertAt, 0, entry);
              if (rankedEntries.length > windowSize) {
                rankedEntries.pop();
              }
            }

            for (let i = 0; i < tasks.length; i += 1) {
              const t = tasks[i];
              const completionTs = getTaskDateTimestamp(t, task => task.completionDate);
              if (!taskMatchesFilters(t, undefined, undefined, completionTs)) {
                continue;
              }

              matchedCount += 1;
              const entry = {
                task: t,
                completionTs: completionTs,
                sortCompletionTs: completionTs === null ? 0 : completionTs,
                scanIndex: i
              };

              if (rankedEntries.length < windowSize) {
                insertCompletionEntry(entry);
                continue;
              }

              const worstEntry = rankedEntries[rankedEntries.length - 1];
              if (compareCompletionEntries(entry, worstEntry) >= 0) {
                continue;
              }
              insertCompletionEntry(entry);
            }

            markListTasks("after_completion_topk", {
              matchedCount: matchedCount,
              retainedCount: rankedEntries.length,
              durationMs: Date.now() - completionPathStart,
              offset: safeOffset,
              limit: limit,
              windowSize: windowSize
            });

            const totalCount = includeTotalCount ? matchedCount : null;
            const pageTasks = rankedEntries.slice(safeOffset, safeOffset + limit).map(entry => entry.task);
            const payloadStart = Date.now();
            const items = pageTasks.map(t => taskToPayload(t, fields));
            markListTasks("after_payload_map", {
              returnedCount: items.length,
              durationMs: Date.now() - payloadStart
            });

            const returnedCount = items.length;
            const hasMore = (safeOffset + items.length) < matchedCount;
            const nextCursor = hasMore ? String(safeOffset + items.length) : null;

            response.data = { items: items, nextCursor: nextCursor, returnedCount: returnedCount };
            if (includeTotalCount) {
              response.data.totalCount = totalCount;
            }
            if (listTasksDebug) {
              listTasksDebug.totalTimingMs = Date.now() - start;
              try {
                writeJSON(basePath + "/logs/list_tasks_debug_" + requestId + ".json", listTasksDebug);
              } catch (debugError) {}
            }
          } else {

            // Filter first, then apply pagination. Cursor semantics are based on the
            // filtered/sorted result set, not the original OmniFocus flattened list.
            const filterPassStart = Date.now();
            tasks = tasks.filter(t => taskMatchesFilters(t, undefined, undefined));
            markListTasks("after_filter_pass", {
              count: tasks.length,
              durationMs: Date.now() - filterPassStart
            });
            const totalCount = includeTotalCount ? tasks.length : null;

            // Sort by completion date descending when filtering by completed tasks
            // This matches OmniFocus Completed perspective behavior
            if (requiresCompletionSort) {
              const sortStart = Date.now();
              tasks.sort((a, b) => {
                const dateA = getTaskDateTimestamp(a, t => t.completionDate) || 0;
                const dateB = getTaskDateTimestamp(b, t => t.completionDate) || 0;
                return dateB - dateA;
              });
              markListTasks("after_completion_sort", {
                count: tasks.length,
                durationMs: Date.now() - sortStart
              });
            }

            // Apply offset + limit to the filtered/sorted task list.
            const pageTasks = tasks.slice(safeOffset, safeOffset + limit);
            markListTasks("after_paging", {
              pageCount: pageTasks.length,
              totalCount: totalCount,
              offset: safeOffset,
              limit: limit
            });
            const payloadStart = Date.now();
            const items = pageTasks.map(t => taskToPayload(t, fields));
            markListTasks("after_payload_map", {
              returnedCount: items.length,
              durationMs: Date.now() - payloadStart
            });

            // Calculate returned count (actual items in this response)
            const returnedCount = items.length;
            
            // Calculate pagination cursor
            const hasMore = (safeOffset + items.length) < tasks.length;
            const nextCursor = hasMore ? String(safeOffset + items.length) : null;
            
            // Build response with both counts
            response.data = { items: items, nextCursor: nextCursor, returnedCount: returnedCount };
            if (includeTotalCount) {
              response.data.totalCount = totalCount;
            }
            if (listTasksDebug) {
              listTasksDebug.totalTimingMs = Date.now() - start;
              try {
                writeJSON(basePath + "/logs/list_tasks_debug_" + requestId + ".json", listTasksDebug);
              } catch (debugError) {}
            }
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
          const debugTaskCounts = filter.search === "__debug_task_counts__";
          const taskCountsDebug = debugTaskCounts ? {
            requestId: requestId,
            op: request.op,
            marks: []
          } : null;
          const markTaskCounts = (label, extra) => {
            if (!taskCountsDebug) { return; }
            const entry = Object.assign({ label: label, ms: Date.now() - start }, extra || {});
            taskCountsDebug.marks.push(entry);
          };

          const inboxView = (typeof filter.inboxView === "string") ? filter.inboxView.toLowerCase() : "available";
          const isEverything = inboxView === "everything";
          const isRemaining = inboxView === "remaining";
          const projectView = (typeof filter.projectView === "string") ? filter.projectView.toLowerCase() : null;

          const availableOnly = (typeof filter.availableOnly === "boolean")
            ? filter.availableOnly
            : (filter.completed === true ? false : !isRemaining && !isEverything);

          function resolveProject(projectFilter) {
            if (!projectFilter || typeof projectFilter !== "string") { return null; }
            return (safe(() => flattenedProjects.find(p => {
              const pid = String(safe(() => p.id.primaryKey) || "");
              const pname = String(safe(() => p.name) || "");
              return pid === projectFilter || pname === projectFilter;
            })) || null);
          }

          function selectTaskPool() {
            if (filter.inboxOnly === true) {
              return inboxTasksArray();
            }

            const project = resolveProject(filter.project);
            if (filter.project && !project) {
              return [];
            }
            if (project) {
              return toTaskArray(safe(() => project.flattenedTasks));
            }

            return toTaskArray(safe(() => flattenedTasks));
          }

          // Use same filtering logic as list_tasks for consistency.
          // Task pool is selected from native OmniFocus collections first,
          // then filtered with the same semantics as list_tasks.
          const poolStart = Date.now();
          let tasks = selectTaskPool();
          const debugInfo = debugTaskCounts ? {
            requestId: requestId,
            availableOnly: availableOnly,
            inboxView: inboxView,
            projectView: projectView,
            initialPoolCount: tasks.length
          } : null;
          markTaskCounts("selected_base_pool", {
            count: tasks.length,
            durationMs: Date.now() - poolStart,
            inboxOnly: filter.inboxOnly === true,
            projectFilter: filter.project || null,
            projectView: projectView,
            availableOnly: availableOnly
          });

          function sampleTask(task) {
            const project = safe(() => task.containingProject);
            const parent = safe(() => task.parent);
            return {
              id: String(safe(() => task.id.primaryKey) || ""),
              name: String(safe(() => task.name) || ""),
              taskStatus: String(taskStatus(task)),
              available: isTaskAvailable(task),
              projectStatus: project ? String(safe(() => project.status) || "") : null,
              parentStatus: parent ? String(taskStatus(parent)) : null
            };
          }

          // Parse filter dates
          const filterState = {
            completed: filter.completed,
            flagged: filter.flagged,
            availableOnly: availableOnly,
            projectFilter: filter.project,
            dueBeforeTs: filter.dueBefore ? safe(() => parseFilterDate(filter.dueBefore, response.warnings).getTime()) : null,
            dueAfterTs: filter.dueAfter ? safe(() => parseFilterDate(filter.dueAfter, response.warnings).getTime()) : null,
            plannedBeforeTs: filter.plannedBefore ? safe(() => parseFilterDate(filter.plannedBefore, response.warnings).getTime()) : null,
            plannedAfterTs: filter.plannedAfter ? safe(() => parseFilterDate(filter.plannedAfter, response.warnings).getTime()) : null,
            deferBeforeTs: filter.deferBefore ? safe(() => parseFilterDate(filter.deferBefore, response.warnings).getTime()) : null,
            deferAfterTs: filter.deferAfter ? safe(() => parseFilterDate(filter.deferAfter, response.warnings).getTime()) : null,
            completedBeforeTs: filter.completedBefore ? safe(() => parseFilterDate(filter.completedBefore, response.warnings).getTime()) : null,
            completedAfterTs: filter.completedAfter ? safe(() => parseFilterDate(filter.completedAfter, response.warnings).getTime()) : null,
            tags: Array.isArray(filter.tags) ? filter.tags : null,
            untaggedOnly: Array.isArray(filter.tags) && filter.tags.length === 0,
            maxEstimatedMinutes: filter.maxEstimatedMinutes,
            minEstimatedMinutes: filter.minEstimatedMinutes
          };

          const statusGateSample = [];
          const availableGateSample = [];
          const finalSample = [];
          let afterStatusGateCount = 0;
          let afterAvailableGateCount = 0;

          const hasProjectScopedFilters = Boolean(filterState.projectFilter) || Boolean(projectView);
          const hasScheduleFilters =
            filterState.dueBeforeTs !== null ||
            filterState.dueAfterTs !== null ||
            filterState.deferBeforeTs !== null ||
            filterState.deferAfterTs !== null ||
            filterState.plannedBeforeTs !== null ||
            filterState.plannedAfterTs !== null;
          const hasTagOrEstimateFilters =
            Boolean(filterState.tags) ||
            filterState.maxEstimatedMinutes !== undefined ||
            filterState.minEstimatedMinutes !== undefined;
          const useSimpleAvailableFastPath =
            filterState.availableOnly &&
            filterState.completed !== true &&
            !hasProjectScopedFilters &&
            !hasScheduleFilters &&
            filterState.completedBeforeTs === null &&
            filterState.completedAfterTs === null &&
            !hasTagOrEstimateFilters;
          const useSimpleCompletedFastPath =
            filterState.completed === true &&
            !filterState.availableOnly &&
            !hasProjectScopedFilters &&
            !hasScheduleFilters &&
            !hasTagOrEstimateFilters;

          const counts = { total: 0, completed: 0, available: 0, flagged: 0 };
          const countPassStart = Date.now();
          if (useSimpleAvailableFastPath) {
            tasks.forEach(t => {
              const taskStatusValue = taskStatus(t);
              const taskCompleted = isCompletedStatusValue(taskStatusValue);
              const taskDropped = isDroppedStatusValue(taskStatusValue);
              if (taskCompleted || taskDropped) { return; }
              afterStatusGateCount += 1;
              if (debugInfo && statusGateSample.length < 5) {
                statusGateSample.push(sampleTask(t));
              }
              if (!isAvailableStatusValue(taskStatusValue)) { return; }

              let taskFlagged = null;
              if (filterState.flagged !== undefined) {
                taskFlagged = Boolean(t.flagged);
                if (taskFlagged !== filterState.flagged) { return; }
              }

              if (!isTaskAvailableWithStatus(t, taskStatusValue, undefined)) { return; }
              afterAvailableGateCount += 1;
              if (debugInfo && availableGateSample.length < 5) {
                availableGateSample.push(sampleTask(t));
              }

              counts.total += 1;
              counts.available += 1;
              if (taskFlagged === null) {
                taskFlagged = Boolean(t.flagged);
              }
              if (taskFlagged) { counts.flagged += 1; }
              if (debugInfo && finalSample.length < 5) {
                finalSample.push(sampleTask(t));
              }
            });
          } else if (useSimpleCompletedFastPath) {
            tasks.forEach(t => {
              const taskStatusValue = taskStatus(t);
              if (!isCompletedStatusValue(taskStatusValue)) { return; }
              afterStatusGateCount += 1;
              if (debugInfo && statusGateSample.length < 5) {
                statusGateSample.push(sampleTask(t));
              }

              if (filterState.completedBeforeTs !== null) {
                const completed = getTaskDateTimestamp(t, task => task.completionDate);
                if (completed === null || completed > filterState.completedBeforeTs) return;
              }
              if (filterState.completedAfterTs !== null) {
                const completed = getTaskDateTimestamp(t, task => task.completionDate);
                if (completed === null || completed < filterState.completedAfterTs) return;
              }

              let taskFlagged = null;
              if (filterState.flagged !== undefined) {
                taskFlagged = Boolean(t.flagged);
                if (taskFlagged !== filterState.flagged) { return; }
              }

              afterAvailableGateCount += 1;
              if (debugInfo && availableGateSample.length < 5) {
                availableGateSample.push(sampleTask(t));
              }

              counts.total += 1;
              counts.completed += 1;
              if (taskFlagged === null) {
                taskFlagged = Boolean(t.flagged);
              }
              if (taskFlagged) { counts.flagged += 1; }
              if (debugInfo && finalSample.length < 5) {
                finalSample.push(sampleTask(t));
              }
            });
          } else {
            tasks.forEach(t => {
              const taskStatusValue = taskStatus(t);
              const taskCompleted = isCompletedStatusValue(taskStatusValue);
              const taskDropped = isDroppedStatusValue(taskStatusValue);
              const taskRemaining = !taskCompleted && !taskDropped;
              let taskFlagged = null;

              if (filterState.completed !== undefined) {
                if (taskCompleted !== filterState.completed) return;
              } else if (!isEverything) {
                if (!taskRemaining) return;
              }
              afterStatusGateCount += 1;
              if (debugInfo && statusGateSample.length < 5) {
                statusGateSample.push(sampleTask(t));
              }

              if (filterState.flagged !== undefined) {
                taskFlagged = Boolean(t.flagged);
                if (taskFlagged !== filterState.flagged) return;
              }
              let project = null;
              if (filterState.projectFilter) {
                project = safe(() => t.containingProject);
                if (!project) return;
                const pid = String(safe(() => project.id.primaryKey) || "");
                const pname = String(safe(() => project.name) || "");
                if (pid !== filterState.projectFilter && pname !== filterState.projectFilter) return;
              }
              if (projectView) {
                if (project === null) {
                  project = safe(() => t.containingProject);
                }
                if (!projectMatchesView(project, projectView, true)) return;
              }
              if (filterState.dueBeforeTs !== null) {
                const due = getTaskDateTimestamp(t, task => task.dueDate);
                if (due === null || due > filterState.dueBeforeTs) return;
              }
              if (filterState.dueAfterTs !== null) {
                const due = getTaskDateTimestamp(t, task => task.dueDate);
                if (due === null || due < filterState.dueAfterTs) return;
              }
              if (filterState.deferBeforeTs !== null) {
                const defer = getTaskDateTimestamp(t, task => task.deferDate);
                if (defer === null || defer > filterState.deferBeforeTs) return;
              }
              if (filterState.deferAfterTs !== null) {
                const defer = getTaskDateTimestamp(t, task => task.deferDate);
                if (defer === null || defer < filterState.deferAfterTs) return;
              }
              if (filterState.plannedBeforeTs !== null) {
                const planned = getTaskDateTimestamp(t, task => task.plannedDate);
                if (planned === null || planned > filterState.plannedBeforeTs) return;
              }
              if (filterState.plannedAfterTs !== null) {
                const planned = getTaskDateTimestamp(t, task => task.plannedDate);
                if (planned === null || planned < filterState.plannedAfterTs) return;
              }
              if (filterState.completedBeforeTs !== null) {
                const completed = getTaskDateTimestamp(t, task => task.completionDate);
                if (completed === null || completed > filterState.completedBeforeTs) return;
              }
              if (filterState.completedAfterTs !== null) {
                const completed = getTaskDateTimestamp(t, task => task.completionDate);
                if (completed === null || completed < filterState.completedAfterTs) return;
              }
              if (filterState.maxEstimatedMinutes !== undefined) {
                const minutes = safe(() => t.estimatedMinutes);
                if (minutes === null || minutes === undefined || minutes > filterState.maxEstimatedMinutes) return;
              }
              if (filterState.minEstimatedMinutes !== undefined) {
                const minutes = safe(() => t.estimatedMinutes);
                if (minutes === null || minutes === undefined || minutes < filterState.minEstimatedMinutes) return;
              }
              if (filterState.tags) {
                const tags = safe(() => t.tags) || [];
                if (filterState.untaggedOnly) {
                  if (tags.length > 0) return;
                } else {
                  const hasMatchingTag = tags.some(tag => {
                    const tagId = String(safe(() => tag.id.primaryKey) || "");
                    const tagName = String(safe(() => tag.name) || "");
                    return filterState.tags.some(filterTag => tagId === filterTag || tagName === filterTag);
                  });
                  if (!hasMatchingTag) return;
                }
              }

              let taskAvailable = false;
              if (filterState.availableOnly || isAvailableStatusValue(taskStatusValue)) {
                taskAvailable = isTaskAvailableWithStatus(t, taskStatusValue, project === null ? undefined : project);
              }
              if (filterState.availableOnly && !taskAvailable) return;

              afterAvailableGateCount += 1;
              if (debugInfo && availableGateSample.length < 5) {
                availableGateSample.push(sampleTask(t));
              }

              counts.total += 1;
              if (taskCompleted) { counts.completed += 1; }
              if (filterState.availableOnly) {
                counts.available += 1;
              } else if (taskAvailable) {
                counts.available += 1;
              }
              if (taskFlagged === null) {
                taskFlagged = Boolean(t.flagged);
              }
              if (taskFlagged) { counts.flagged += 1; }
              if (debugInfo && finalSample.length < 5) {
                finalSample.push(sampleTask(t));
              }
            });
          }
          markTaskCounts("after_count_pass", {
            count: counts.total,
            durationMs: Date.now() - countPassStart,
            afterStatusGateCount: afterStatusGateCount,
            afterAvailableGateCount: afterAvailableGateCount,
            counts: counts
          });
          if (debugInfo) {
            debugInfo.afterCompletedFilterCount = afterStatusGateCount;
            debugInfo.afterCompletedFilterSample = statusGateSample;
            debugInfo.afterAvailableFilterCount = afterAvailableGateCount;
            debugInfo.afterAvailableFilterSample = availableGateSample;
            debugInfo.afterAllFiltersCount = counts.total;
            debugInfo.afterAllFiltersSample = finalSample;
          }
          if (debugInfo) {
            debugInfo.counts = counts;
            taskCountsDebug.debugInfo = debugInfo;
            taskCountsDebug.totalTimingMs = Date.now() - start;
            try {
              writeJSON(basePath + "/logs/get_task_counts_debug_" + requestId + ".json", taskCountsDebug);
            } catch (debugError) {}
          }

          response.data = counts;
} else if (request.op === "get_project_counts") {
          const filter = request.filter || {};
          const debugProjectCounts = filter.search === "__debug_project_counts__";
          const projectCountsDebug = debugProjectCounts ? {
            requestId: requestId,
            op: request.op,
            marks: []
          } : null;
          const markProjectCounts = (label, extra) => {
            if (!projectCountsDebug) { return; }
            const entry = Object.assign({ label: label, ms: Date.now() - start }, extra || {});
            projectCountsDebug.marks.push(entry);
          };
          
          // Check if this is a completion date query
          const completedAfter = filter.completedAfter ? parseFilterDate(filter.completedAfter, response.warnings) : null;
          const completedBefore = filter.completedBefore ? parseFilterDate(filter.completedBefore, response.warnings) : null;
          const completedOnly = filter.completed === true;
          
          if (completedOnly || completedAfter || completedBefore) {
            // Count completed projects by completion date
            const completedProjectsStart = Date.now();
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
            markProjectCounts("selected_completed_projects", {
              count: projects.length,
              durationMs: Date.now() - completedProjectsStart
            });
            
            const projectCount = projects.length;
            
            // Count completed tasks in those projects
            const projectIds = new Set(projects.map(p => String(safe(() => p.id.primaryKey) || "")));
            let completedTaskCount = 0;
            const completedTaskCountStart = Date.now();
            
            flattenedTasks.forEach(t => {
              const project = safe(() => t.containingProject);
              if (!project) { return; }
              const pid = String(safe(() => project.id.primaryKey) || "");
              if (projectIds.has(pid) && isCompletedStatus(t)) {
                const taskCompletionDate = getTaskDateTimestamp(t, task => task.completionDate);
                if (taskCompletionDate === null) { return; }
                // Only count tasks completed in the same window
                if ((!completedAfter || taskCompletionDate >= completedAfter.getTime()) &&
                    (!completedBefore || taskCompletionDate < completedBefore.getTime())) {
                  completedTaskCount++;
                }
              }
            });
            markProjectCounts("counted_completed_tasks", {
              durationMs: Date.now() - completedTaskCountStart,
              projectCount: projectCount,
              actionCount: completedTaskCount
            });
            
            response.data = { projects: projectCount, actions: completedTaskCount };
          } else {
            const rawProjectView = (typeof filter.projectView === "string") ? filter.projectView.toLowerCase() : "remaining";
            const projectStatusView = (
              rawProjectView === "active" ||
              rawProjectView === "onhold" ||
              rawProjectView === "on_hold" ||
              rawProjectView === "dropped" ||
              rawProjectView === "done" ||
              rawProjectView === "completed" ||
              rawProjectView === "everything" ||
              rawProjectView === "all"
            ) ? rawProjectView : null;

            const derivedCompleted = (typeof filter.completed === "boolean")
              ? filter.completed
              : (rawProjectView === "everything" ? undefined : false);
            const derivedAvailableOnly = (typeof filter.availableOnly === "boolean")
              ? filter.availableOnly
              : (rawProjectView === "available");

            function resolveProject(projectFilter) {
              if (!projectFilter || typeof projectFilter !== "string") { return null; }
              return (safe(() => flattenedProjects.find(p => {
                const pid = String(safe(() => p.id.primaryKey) || "");
                const pname = String(safe(() => p.name) || "");
                return pid === projectFilter || pname === projectFilter;
              })) || null);
            }

            let tasks = [];
            const project = resolveProject(filter.project);
            if (filter.project && !project) {
              tasks = [];
            } else if (project) {
              const poolStart = Date.now();
              tasks = toTaskArray(safe(() => project.flattenedTasks));
              markProjectCounts("selected_base_pool", {
                count: tasks.length,
                durationMs: Date.now() - poolStart,
                projectFilter: filter.project,
                projectView: rawProjectView,
                availableOnly: derivedAvailableOnly,
                completed: derivedCompleted
              });
            } else {
              const poolStart = Date.now();
              tasks = toTaskArray(safe(() => flattenedTasks));
              markProjectCounts("selected_base_pool", {
                count: tasks.length,
                durationMs: Date.now() - poolStart,
                projectFilter: null,
                projectView: rawProjectView,
                availableOnly: derivedAvailableOnly,
                completed: derivedCompleted
              });
            }

            const filterState = {
              completed: derivedCompleted,
              flagged: filter.flagged,
              availableOnly: derivedAvailableOnly,
              projectFilter: filter.project,
              projectView: projectStatusView,
              dueBefore: filter.dueBefore ? parseFilterDate(filter.dueBefore, response.warnings) : null,
              dueAfter: filter.dueAfter ? parseFilterDate(filter.dueAfter, response.warnings) : null,
              plannedBefore: filter.plannedBefore ? parseFilterDate(filter.plannedBefore, response.warnings) : null,
              plannedAfter: filter.plannedAfter ? parseFilterDate(filter.plannedAfter, response.warnings) : null,
              deferBefore: filter.deferBefore ? parseFilterDate(filter.deferBefore, response.warnings) : null,
              deferAfter: filter.deferAfter ? parseFilterDate(filter.deferAfter, response.warnings) : null,
              completedBefore: filter.completedBefore ? parseFilterDate(filter.completedBefore, response.warnings) : null,
              completedAfter: filter.completedAfter ? parseFilterDate(filter.completedAfter, response.warnings) : null,
              tags: Array.isArray(filter.tags) ? filter.tags : null,
              untaggedOnly: Array.isArray(filter.tags) && filter.tags.length === 0,
              maxEstimatedMinutes: filter.maxEstimatedMinutes,
              minEstimatedMinutes: filter.minEstimatedMinutes
            };

            const projectIds = new Set();
            let actionCount = 0;
            const countPassStart = Date.now();
            tasks.forEach(t => {
              const project = safe(() => t.containingProject);
              if (!project) { return; }

              if (filterState.completed !== undefined) {
                if (isCompletedStatus(t) !== filterState.completed) return;
              } else if (rawProjectView !== "everything") {
                if (!isRemainingStatus(t)) return;
              }

              if (filterState.flagged !== undefined) {
                if (Boolean(t.flagged) !== filterState.flagged) return;
              }
              if (filterState.availableOnly) {
                if (!isTaskAvailable(t)) return;
              }
              if (filterState.projectFilter) {
                const pid = String(safe(() => project.id.primaryKey) || "");
                const pname = String(safe(() => project.name) || "");
                if (pid !== filterState.projectFilter && pname !== filterState.projectFilter) return;
              }
              if (filterState.projectView) {
                if (!projectMatchesView(project, filterState.projectView, true)) return;
              }
              if (filterState.dueBefore) {
                const due = getTaskDateTimestamp(t, task => task.dueDate);
                if (due === null || due > filterState.dueBefore.getTime()) return;
              }
              if (filterState.dueAfter) {
                const due = getTaskDateTimestamp(t, task => task.dueDate);
                if (due === null || due < filterState.dueAfter.getTime()) return;
              }
              if (filterState.deferBefore) {
                const defer = getTaskDateTimestamp(t, task => task.deferDate);
                if (defer === null || defer > filterState.deferBefore.getTime()) return;
              }
              if (filterState.deferAfter) {
                const defer = getTaskDateTimestamp(t, task => task.deferDate);
                if (defer === null || defer < filterState.deferAfter.getTime()) return;
              }
              if (filterState.plannedBefore) {
                const planned = getTaskDateTimestamp(t, task => task.plannedDate);
                if (planned === null || planned > filterState.plannedBefore.getTime()) return;
              }
              if (filterState.plannedAfter) {
                const planned = getTaskDateTimestamp(t, task => task.plannedDate);
                if (planned === null || planned < filterState.plannedAfter.getTime()) return;
              }
              if (filterState.completedBefore) {
                const completed = getTaskDateTimestamp(t, task => task.completionDate);
                if (completed === null || completed > filterState.completedBefore.getTime()) return;
              }
              if (filterState.completedAfter) {
                const completed = getTaskDateTimestamp(t, task => task.completionDate);
                if (completed === null || completed < filterState.completedAfter.getTime()) return;
              }
              if (filterState.maxEstimatedMinutes !== undefined) {
                const minutes = safe(() => t.estimatedMinutes);
                if (minutes === null || minutes === undefined || minutes > filterState.maxEstimatedMinutes) return;
              }
              if (filterState.minEstimatedMinutes !== undefined) {
                const minutes = safe(() => t.estimatedMinutes);
                if (minutes === null || minutes === undefined || minutes < filterState.minEstimatedMinutes) return;
              }
              if (filterState.tags) {
                const tags = safe(() => t.tags) || [];
                if (filterState.untaggedOnly) {
                  if (tags.length > 0) return;
                } else {
                  const hasMatchingTag = tags.some(tag => {
                    const tagId = String(safe(() => tag.id.primaryKey) || "");
                    const tagName = String(safe(() => tag.name) || "");
                    return filterState.tags.some(filterTag => tagId === filterTag || tagName === filterTag);
                  });
                  if (!hasMatchingTag) return;
                }
              }
              const pid = String(safe(() => project.id.primaryKey) || "");
              if (pid) { projectIds.add(pid); }
              actionCount += 1;
            });
            markProjectCounts("after_count_pass", {
              durationMs: Date.now() - countPassStart,
              count: actionCount,
              projectCount: projectIds.size,
              actionCount: actionCount
            });

            response.data = { projects: projectIds.size, actions: actionCount };
          }
          if (projectCountsDebug) {
            projectCountsDebug.totalTimingMs = Date.now() - start;
            projectCountsDebug.responseData = response.data;
            try {
              writeJSON(basePath + "/logs/get_project_counts_debug_" + requestId + ".json", projectCountsDebug);
            } catch (debugError) {}
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
