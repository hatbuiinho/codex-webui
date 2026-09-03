<script lang="ts">
  import {
    ChevronDown,
    ChevronRight,
    File,
    Folder,
    FolderOpen,
    Pencil,
    RefreshCw,
    Trash2,
    X
  } from "lucide-svelte";

  import type { DirectoryEntry, DirectoryPayload } from "$lib/types";

  type DirectoryState = {
    entries: DirectoryEntry[];
    loading: boolean;
    error: string;
  };

  let {
    rootPath,
    readOnly = false,
    onClose,
    onDelete,
    onLoadDirectory,
    onOpenFile,
    onRename
  }: {
    rootPath: string;
    readOnly?: boolean;
    onClose: () => void;
    onDelete: (entry: DirectoryEntry) => void | Promise<void>;
    onLoadDirectory: (path: string) => Promise<DirectoryPayload>;
    onOpenFile: (path: string) => void;
    onRename: (entry: DirectoryEntry) => void | Promise<void>;
  } = $props();

  let rootState = $state<DirectoryState>({ entries: [], loading: false, error: "" });
  let childrenByPath = $state<Record<string, DirectoryState>>({});
  let expandedPaths = $state<Record<string, boolean>>({});
  let loadedRootPath = "";

  function describeError(error: unknown) {
    return error instanceof Error ? error.message : String(error);
  }

  async function loadRoot() {
    const nextRoot = rootPath.trim();
    if (!nextRoot) {
      return;
    }
    loadedRootPath = nextRoot;
    rootState = { entries: [], loading: true, error: "" };
    try {
      const payload = await onLoadDirectory(nextRoot);
      if (loadedRootPath !== nextRoot) {
        return;
      }
      rootState = { entries: payload.entries, loading: false, error: "" };
    } catch (error) {
      if (loadedRootPath === nextRoot) {
        rootState = { entries: [], loading: false, error: describeError(error) };
      }
    }
  }

  async function loadChildren(path: string) {
    childrenByPath = {
      ...childrenByPath,
      [path]: { entries: [], loading: true, error: "" }
    };
    try {
      const payload = await onLoadDirectory(path);
      childrenByPath = {
        ...childrenByPath,
        [path]: { entries: payload.entries, loading: false, error: "" }
      };
    } catch (error) {
      childrenByPath = {
        ...childrenByPath,
        [path]: { entries: [], loading: false, error: describeError(error) }
      };
    }
  }

  function toggleDirectory(entry: DirectoryEntry) {
    const expanded = !expandedPaths[entry.path];
    expandedPaths = { ...expandedPaths, [entry.path]: expanded };
    if (expanded && !childrenByPath[entry.path]) {
      void loadChildren(entry.path);
    }
  }

  function refresh() {
    childrenByPath = {};
    expandedPaths = {};
    void loadRoot();
  }

  $effect(() => {
    if (rootPath.trim() && rootPath.trim() !== loadedRootPath) {
      void loadRoot();
    }
  });
</script>

<aside class="workspace-explorer h-full w-[19rem] min-w-[19rem] max-w-[22rem] border-l border-gray-200 bg-white">
  <header class="flex items-center justify-between border-b border-gray-100 px-3 py-3">
    <div class="min-w-0">
      <h2 class="text-xs font-bold uppercase tracking-widest text-gray-700">Explorer</h2>
      <p class="mt-0.5 truncate font-mono text-[10px] text-gray-400" title={rootPath}>{rootPath}</p>
    </div>
    <div class="flex shrink-0 items-center gap-0.5">
      <button class="rounded-md p-1.5 text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-700" onclick={refresh} title="Refresh files" type="button">
        <RefreshCw size={14} class={rootState.loading ? "animate-spin" : ""} />
      </button>
      <button class="rounded-md p-1.5 text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-700" onclick={onClose} title="Hide explorer" type="button">
        <X size={15} />
      </button>
    </div>
  </header>

  <div class="h-[calc(100%-3.75rem)] overflow-y-auto py-2">
    {#if rootState.loading}
      <div class="flex items-center gap-2 px-3 py-3 text-xs text-gray-400"><RefreshCw size={14} class="animate-spin" /> Loading workspace…</div>
    {:else if rootState.error}
      <div class="px-3 py-3 text-xs leading-5 text-red-600">{rootState.error}</div>
    {:else if rootState.entries.length === 0}
      <div class="px-3 py-3 text-xs text-gray-400">This folder is empty.</div>
    {:else}
      {@render renderEntries(rootState.entries, 0)}
    {/if}
  </div>
</aside>

{#snippet renderEntries(entries: DirectoryEntry[], depth: number)}
  {#each entries as entry (entry.path)}
    {@const childState = childrenByPath[entry.path]}
    <div>
      <div class="group flex min-w-0 items-center gap-1 pr-1 hover:bg-amber-50/70" style={`padding-left:${0.5 + depth * 0.9}rem`}>
        {#if entry.isDirectory}
          <button
            aria-label={expandedPaths[entry.path] ? `Collapse ${entry.name}` : `Expand ${entry.name}`}
            class="flex h-7 w-5 shrink-0 items-center justify-center text-gray-400 hover:text-gray-700"
            onclick={() => toggleDirectory(entry)}
            type="button"
          >
            {#if expandedPaths[entry.path]}<ChevronDown size={14} />{:else}<ChevronRight size={14} />{/if}
          </button>
          <button class="flex min-w-0 flex-1 items-center gap-1.5 py-1.5 text-left text-xs font-medium text-gray-700" onclick={() => toggleDirectory(entry)} title={entry.path} type="button">
            {#if expandedPaths[entry.path]}<FolderOpen size={14} class="shrink-0 text-amber-600" />{:else}<Folder size={14} class="shrink-0 text-amber-600" />{/if}
            <span class="truncate">{entry.name}</span>
          </button>
        {:else}
          <span class="w-5 shrink-0"></span>
          <button class="flex min-w-0 flex-1 items-center gap-1.5 py-1.5 text-left text-xs text-gray-700" onclick={() => onOpenFile(entry.path)} title={entry.path} type="button">
            <File size={14} class="shrink-0 text-sky-600" />
            <span class="truncate">{entry.name}</span>
          </button>
        {/if}
        {#if !readOnly}
          <div class="flex shrink-0 opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
            <button class="rounded p-1 text-gray-400 hover:bg-white hover:text-amber-700" onclick={() => void onRename(entry)} title={`Rename ${entry.name}`} type="button"><Pencil size={12} /></button>
            <button class="rounded p-1 text-gray-400 hover:bg-white hover:text-red-600" onclick={() => void onDelete(entry)} title={`Delete ${entry.name}`} type="button"><Trash2 size={12} /></button>
          </div>
        {/if}
      </div>
      {#if entry.isDirectory && expandedPaths[entry.path]}
        {#if childState?.loading}
          <div class="flex items-center gap-1.5 py-1 text-[11px] text-gray-400" style={`padding-left:${2.15 + depth * 0.9}rem`}><RefreshCw size={12} class="animate-spin" /> Loading…</div>
        {:else if childState?.error}
          <div class="py-1 text-[11px] text-red-600" style={`padding-left:${2.15 + depth * 0.9}rem`}>{childState.error}</div>
        {:else if childState}
          {@render renderEntries(childState.entries, depth + 1)}
        {/if}
      {/if}
    </div>
  {/each}
{/snippet}
