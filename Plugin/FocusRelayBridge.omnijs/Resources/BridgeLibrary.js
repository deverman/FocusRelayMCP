(() => {
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
        completed: hasField("completed") ? Boolean(t.completed) : null,
        flagged: hasField("flagged") ? Boolean(t.flagged) : null,
        estimatedMinutes: hasField("estimatedMinutes") ? t.estimatedMinutes : null,
        available: hasField("available") ? isAvailable(t) : null
      };
    }

    function isTaskAvailable(task) {
      const blocked = safe(() => task.blocked);
      if (blocked === true) { return false; }
      const deferDate = safe(() => task.effectiveDeferDate);
      if (deferDate) {
        return deferDate.getTime() <= Date.now();
      }
      return true;
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
          } else if (!useInbox && !(typeof filter.project === "string" && filter.project.length > 0)) {
            response.ok = false;
            response.error = { code: "MISSING_FILTER", message: "project filter is required when inboxOnly is false" };
            response.timingMs = Date.now() - start;
            writeJSON(responsePath, response);
            removeFile(lockPath);
            removeFile(requestPath);
            return;
          }

          const inboxView = (typeof filter.inboxView === "string") ? filter.inboxView.toLowerCase() : "available";
          const isEverything = inboxView === "everything";
          const isRemaining = inboxView === "remaining";

          if (typeof filter.completed === "boolean") {
            tasks = tasks.filter(t => Boolean(t.completed) === filter.completed);
          } else if (!isEverything) {
            tasks = tasks.filter(t => !Boolean(t.completed));
          }

          if (!isEverything) {
            tasks = tasks.filter(t => !t.dropDate);
            tasks = tasks.filter(t => {
              const parent = safe(() => t.parent);
              if (!parent) { return true; }
              if (safe(() => parent.dropDate)) { return false; }
              if (Boolean(safe(() => parent.completed))) { return false; }
              return true;
            });
          }

          const availableOnly = (typeof filter.availableOnly === "boolean") ? filter.availableOnly : !isRemaining && !isEverything;
          if (availableOnly) {
            tasks = tasks.filter(t => isTaskAvailable(t));
          }

          // Date range filters
          // Robust date parsing helper that handles ISO8601 strings from Swift
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
            // Ensure it's a valid Date object with getTime method
            if (typeof date.getTime !== "function") return null;
            const ts = date.getTime();
            if (isNaN(ts)) return null;
            return ts;
          }

          if (filter.dueBefore) {
            const dueBeforeDate = parseFilterDate(filter.dueBefore, response.warnings);
            if (dueBeforeDate) {
              const cutoff = dueBeforeDate.getTime();
              tasks = tasks.filter(t => {
                const dueTs = getTaskDateTimestamp(t, task => task.dueDate);
                return dueTs !== null && dueTs <= cutoff;
              });
            }
          }
          if (filter.dueAfter) {
            const dueAfterDate = parseFilterDate(filter.dueAfter, response.warnings);
            if (dueAfterDate) {
              const cutoff = dueAfterDate.getTime();
              tasks = tasks.filter(t => {
                const dueTs = getTaskDateTimestamp(t, task => task.dueDate);
                return dueTs !== null && dueTs >= cutoff;
              });
            }
          }
          if (filter.deferBefore) {
            const deferBeforeDate = parseFilterDate(filter.deferBefore, response.warnings);
            if (deferBeforeDate) {
              const cutoff = deferBeforeDate.getTime();
              tasks = tasks.filter(t => {
                const deferTs = getTaskDateTimestamp(t, task => task.deferDate);
                return deferTs !== null && deferTs <= cutoff;
              });
            }
          }
          if (filter.deferAfter) {
            const deferAfterDate = parseFilterDate(filter.deferAfter, response.warnings);
            if (deferAfterDate) {
              const cutoff = deferAfterDate.getTime();
              tasks = tasks.filter(t => {
                const deferTs = getTaskDateTimestamp(t, task => task.deferDate);
                return deferTs !== null && deferTs >= cutoff;
              });
            }
          }
          if (filter.completedBefore) {
            const completedBeforeDate = parseFilterDate(filter.completedBefore, response.warnings);
            if (completedBeforeDate) {
              const cutoff = completedBeforeDate.getTime();
              tasks = tasks.filter(t => {
                const completedTs = getTaskDateTimestamp(t, task => task.completionDate);
                return completedTs !== null && completedTs <= cutoff;
              });
            }
          }
          if (filter.completedAfter) {
            const completedAfterDate = parseFilterDate(filter.completedAfter, response.warnings);
            if (completedAfterDate) {
              const cutoff = completedAfterDate.getTime();
              tasks = tasks.filter(t => {
                const completedTs = getTaskDateTimestamp(t, task => task.completionDate);
                return completedTs !== null && completedTs >= cutoff;
              });
            }
          }

          // Duration filters
          if (typeof filter.maxEstimatedMinutes === "number") {
            tasks = tasks.filter(t => {
              const minutes = safe(() => t.estimatedMinutes);
              return minutes !== null && minutes !== undefined && minutes <= filter.maxEstimatedMinutes;
            });
          }
          if (typeof filter.minEstimatedMinutes === "number") {
            tasks = tasks.filter(t => {
              const minutes = safe(() => t.estimatedMinutes);
              return minutes !== null && minutes !== undefined && minutes >= filter.minEstimatedMinutes;
            });
          }

          // Tag filtering
          if (Array.isArray(filter.tags) && filter.tags.length > 0) {
            const tagFilter = filter.tags;
            tasks = tasks.filter(t => {
              const tags = safe(() => t.tags) || [];
              return tags.some(tag => {
                const tagId = String(safe(() => tag.id.primaryKey) || "");
                const tagName = String(safe(() => tag.name) || "");
                return tagFilter.some(filterTag => tagId === filterTag || tagName === filterTag);
              });
            });
          }

          const limit = request.page && request.page.limit ? request.page.limit : 50;
          let offset = 0;
          if (request.page && request.page.cursor) {
            const parsed = parseInt(request.page.cursor, 10);
            if (!isNaN(parsed) && parsed >= 0) { offset = parsed; }
          }

          const slice = tasks.slice(offset, offset + limit);
          const items = slice.map(t => taskToPayload(t, fields));

          const nextCursor = (offset + limit < tasks.length) ? String(offset + limit) : null;
          response.data = { items: items, nextCursor: nextCursor };
        } else if (request.op === "list_projects") {
          const fields = request.fields || [];
          const hasField = (name) => fields.length === 0 || fields.indexOf(name) !== -1;
          const view = (typeof request.filter?.projectView === "string") ? request.filter.projectView.toLowerCase() : "remaining";
          const isEverything = view === "everything";
          const isAvailable = view === "available";
          let projects = flattenedProjects;
          if (!isEverything) {
            projects = projects.filter(p => !Boolean(p.completed));
            projects = projects.filter(p => !p.dropDate);
          }
          if (isAvailable) {
            projects = projects.filter(p => !p.onHold);
          }
          const limit = request.page && request.page.limit ? request.page.limit : 150;
          let offset = 0;
          if (request.page && request.page.cursor) {
            const parsed = parseInt(request.page.cursor, 10);
            if (!isNaN(parsed) && parsed >= 0) { offset = parsed; }
          }
          const slice = projects.slice(offset, offset + limit);
          const items = slice.map(p => {
            return {
              id: hasField("id") ? String(safe(() => p.id.primaryKey) || "") : null,
              name: hasField("name") ? String(safe(() => p.name) || "") : null,
              note: hasField("note") ? safe(() => p.note) : null,
              status: hasField("status") ? String(safe(() => p.status) || "") : null,
              flagged: hasField("flagged") ? Boolean(p.flagged) : null
            };
          });
          const nextCursor = (offset + limit < projects.length) ? String(offset + limit) : null;
          response.data = { items: items, nextCursor: nextCursor, totalCount: projects.length };
        } else if (request.op === "list_tags") {
          const tags = flattenedTags;
          const limit = request.page && request.page.limit ? request.page.limit : 150;
          let offset = 0;
          if (request.page && request.page.cursor) {
            const parsed = parseInt(request.page.cursor, 10);
            if (!isNaN(parsed) && parsed >= 0) { offset = parsed; }
          }
          const slice = tags.slice(offset, offset + limit);
          const items = slice.map(tag => {
            return {
              id: String(safe(() => tag.id.primaryKey) || ""),
              name: String(safe(() => tag.name) || "")
            };
          });
          const nextCursor = (offset + limit < tags.length) ? String(offset + limit) : null;
          response.data = { items: items, nextCursor: nextCursor, totalCount: tags.length };
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
          const inboxOnly = filter.inboxOnly === true;
          const tasks = inboxOnly ? (function(){
            const arr = [];
            inbox.apply(task => arr.push(task));
            return arr;
          })() : flattenedTasks;

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
          const view = (typeof filter.projectView === "string") ? filter.projectView.toLowerCase() : "remaining";
          const isEverything = view === "everything";
          const isAvailableView = view === "available";

          function status(task) {
            return safe(() => task.taskStatus);
          }

          function isRemainingStatus(task) {
            const st = status(task);
            return st !== Task.Status.Completed && st !== Task.Status.Dropped;
          }

          function isAvailableStatus(task) {
            const st = status(task);
            return st === Task.Status.Available ||
              st === Task.Status.DueSoon ||
              st === Task.Status.Next ||
              st === Task.Status.Overdue;
          }

          function projectAllowed(p) {
            if (!p) { return false; }
            if (!isEverything) {
              if (Boolean(safe(() => p.completed))) { return false; }
              if (safe(() => p.dropDate)) { return false; }
            }
            if (view === "remaining" || isAvailableView) {
              if (Boolean(safe(() => p.onHold))) { return false; }
            }
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
