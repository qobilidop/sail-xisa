<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { EditorState } from '@codemirror/state';
  import { EditorView, keymap, lineNumbers, highlightActiveLine } from '@codemirror/view';
  import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
  import { oneDark } from '@codemirror/theme-one-dark';

  let {
    source = $bindable(''),
    currentLine = $bindable(-1),
  }: {
    source: string;
    currentLine: number;
  } = $props();

  const examples: Record<string, string> = {
    'Simple Arithmetic': `; Simple arithmetic: add two numbers
MOVI PR0, 10
MOVI PR1, 25
ADD PR2, PR0, PR1
HALT`,
    'Branch Example': `; Countdown loop from 5 to 0
MOVI PR0, 5
MOVI PR1, 1
loop:
SUB PR0, PR0, PR1
BNZ loop
HALT`,
    'Extract Packet': `; Extract a field from the packet header
MOVI PR0, 0
EXT.CD PR1, PR0, 8, 8
HALT`,
  };

  let editorContainer: HTMLDivElement;
  let view: EditorView | undefined;
  let selectedExample = $state('');

  const updateListener = EditorView.updateListener.of((update) => {
    if (update.docChanged) {
      source = update.state.doc.toString();
    }
  });

  onMount(() => {
    const state = EditorState.create({
      doc: source,
      extensions: [
        lineNumbers(),
        highlightActiveLine(),
        history(),
        keymap.of([...defaultKeymap, ...historyKeymap]),
        oneDark,
        updateListener,
        EditorView.theme({
          '&': { fontSize: '14px' },
          '.cm-content': { fontFamily: 'var(--font-mono)' },
          '.cm-gutters': { fontFamily: 'var(--font-mono)' },
        }),
      ],
    });
    view = new EditorView({ state, parent: editorContainer });
  });

  onDestroy(() => {
    view?.destroy();
  });

  function loadExample(name: string) {
    if (!name || !view) return;
    const text = examples[name] || '';
    view.dispatch({
      changes: { from: 0, to: view.state.doc.length, insert: text },
    });
    source = text;
  }

  // Highlight current line when it changes
  $effect(() => {
    if (!view || currentLine < 0) return;
    const line = view.state.doc.line(currentLine + 1); // 1-based
    view.dispatch({
      selection: { anchor: line.from },
      scrollIntoView: true,
    });
  });
</script>

<div class="editor-section">
  <div class="editor-toolbar">
    <label for="example-select">Examples:</label>
    <select
      id="example-select"
      bind:value={selectedExample}
      onchange={() => loadExample(selectedExample)}
    >
      <option value="">— select —</option>
      {#each Object.keys(examples) as name}
        <option value={name}>{name}</option>
      {/each}
    </select>
  </div>
  <div class="editor-container" bind:this={editorContainer}></div>
</div>
