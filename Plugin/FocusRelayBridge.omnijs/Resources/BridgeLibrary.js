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
        completionDate: hasField("completionDate") ? (safe(() => t.completionDate) ? t.completionDate.toISOString() : null) : null,
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
          }
          // Note: When inboxOnly is false and no project filter is specified,
          // we return tasks from all projects (flattenedTasks)

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
          
          // Handle staleThreshold - mutually exclusive with deferBefore
          // Converts staleThreshold to deferBefore date (today - threshold days) in user's timezone
          if (filter.staleThreshold && !filter.deferBefore) {
            const threshold = filter.staleThreshold;
            let days = 30; // default
            switch (threshold) {
              case "7days": days = 7; break;
              case "30days": days = 30; break;
              case "90days": days = 90; break;
              case "180days": days = 180; break;
              case "270days": days = 270; break;
              case "365days": days = 365; break;
            }
            const cutoffDate = new Date(Date.now() - (days * 24 * 60 * 60 * 1000));
            filter.deferBefore = cutoffDate.toISOString();
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
            
            // Duration filters
            maxEstimatedMinutes: filter.maxEstimatedMinutes,
            minEstimatedMinutes: filter.minEstimatedMinutes,
            
            // Tag filters
            tags: Array.isArray(filter.tags) ? filter.tags : null,
            untaggedOnly: Array.isArray(filter.tags) && filter.tags.length === 0
          };
          
          // Single-pass filter with all conditions
          const filteredTasks = [];
          const limit = request.page && request.page.limit ? request.page.limit : 50;
          
          for (let i = 0; i < tasks.length && filteredTasks.length < limit; i++) {
            const t = tasks[i];
            
            // Status checks
            if (filterState.completed !== undefined) {
              const taskCompleted = Boolean(t.completed);
              if (taskCompleted !== filterState.completed) continue;
            }
            if (filterState.flagged !== undefined) {
              const taskFlagged = Boolean(t.flagged);
              if (taskFlagged !== filterState.flagged) continue;
            }
            if (filterState.availableOnly) {
              if (!isTaskAvailable(t)) continue;
            }
            
            // Project check
            if (filterState.projectFilter) {
              const project = safe(() => t.containingProject);
              if (!project) continue;
              const pid = String(safe(() => project.id.primaryKey) || "");
              const pname = String(safe(() => project.name) || "");
              if (pid !== filterState.projectFilter && pname !== filterState.projectFilter) continue;
            }
            
            // Date checks
            if (filterState.dueBefore) {
              const due = getTaskDateTimestamp(t, task => task.dueDate);
              if (due === null || due > filterState.dueBefore.getTime()) continue;
            }
            if (filterState.dueAfter) {
              const due = getTaskDateTimestamp(t, task => task.dueDate);
              if (due === null || due < filterState.dueAfter.getTime()) continue;
            }
            if (filterState.deferBefore) {
              const defer = getTaskDateTimestamp(t, task => task.deferDate);
              if (defer === null || defer > filterState.deferBefore.getTime()) continue;
            }
            if (filterState.deferAfter) {
              const defer = getTaskDateTimestamp(t, task => task.deferDate);
              if (defer === null || defer < filterState.deferAfter.getTime()) continue;
            }
            
            // Duration checks
            if (filterState.maxEstimatedMinutes !== undefined) {
              const minutes = safe(() => t.estimatedMinutes);
              if (minutes === null || minutes === undefined || minutes > filterState.maxEstimatedMinutes) continue;
            }
            if (filterState.minEstimatedMinutes !== undefined) {
              const minutes = safe(() => t.estimatedMinutes);
              if (minutes === null || minutes === undefined || minutes < filterState.minEstimatedMinutes) continue;
            }
            
            // Tag checks
            if (filterState.tags) {
              const tags = safe(() => t.tags) || [];
              if (filterState.untaggedOnly) {
                if (tags.length > 0) continue;
              } else {
                const hasMatchingTag = tags.some(tag => {
                  const tagId = String(safe(() => tag.id.primaryKey) || "");
                  const tagName = String(safe(() => tag.name) || "");
                  return filterState.tags.some(filterTag => tagId === filterTag || tagName === filterTag);
                });
                if (!hasMatchingTag) continue;
              }
            }
            
            filteredTasks.push(t);
          }
          
          tasks = filteredTasks;
          
          // Apply offset for pagination (tasks already limited to page size during filtering)
          const offset = request.page && request.page.cursor ? parseInt(request.page.cursor, 10) : 0;
          const pageTasks = offset > 0 ? tasks.slice(offset) : tasks;
          const items = pageTasks.map(t => taskToPayload(t, fields));
          
          // Calculate total available for pagination
          // Note: tasks.length is limited to page size, so we need to indicate there may be more
          // For accurate pagination, we'd need to scan all tasks (trade-off for performance)
          const hasMore = items.length === limit;
          const nextCursor = hasMore ? String(offset + items.length) : null;
          
          response.data = { items: items, nextCursor: nextCursor };
        } else if (request.op === "list_projects") {
          const fields = request.fields || [];
          const hasField = (name) => fields.length === 0 || fields.indexOf(name) !== -1;
          // Check both projectFilter and filter (Swift sends projectFilter)
          const filter = request.projectFilter || request.filter || {};
          const statusFilter = (typeof filter.statusFilter === "string") ? filter.statusFilter.toLowerCase() : "active";
          const includeTaskCounts = filter.includeTaskCounts === true;
          
          let projects = flattenedProjects;
          
          // Filter by status using Project.Status enum
          if (statusFilter !== "all") {
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
          
          const limit = request.page && request.page.limit ? request.page.limit : 150;
          let offset = 0;
          if (request.page && request.page.cursor) {
            const parsed = parseInt(request.page.cursor, 10);
            if (!isNaN(parsed) && parsed >= 0) { offset = parsed; }
          }
          
          const slice = projects.slice(offset, offset + limit);
          
          const items = slice.map(p => {
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
            
            const item = {
              id: hasField("id") ? String(safe(() => p.id.primaryKey) || "") : null,
              name: hasField("name") ? String(safe(() => p.name) || "") : null,
              note: hasField("note") ? safe(() => p.note) : null,
              status: hasField("status") ? getProjectStatusString(p) : null,
              flagged: hasField("flagged") ? Boolean(p.flagged) : null
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
              
              item.taskCounts = {
                available: available,
                remaining: remaining,
                completed: completed,
                dropped: dropped,
                total: flattenedTasks.length
              };

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
          response.data = { items: items, nextCursor: nextCursor, totalCount: projects.length };
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
