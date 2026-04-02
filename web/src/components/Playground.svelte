<script lang="ts">
  import { onMount } from 'svelte';
  import Editor from './Editor.svelte';
  import Controls from './Controls.svelte';
  import StateViewer from './StateViewer.svelte';
  import { getSimulator } from '../lib/wasm';

  let source = $state('');
  let state: any = $state(null);
  let prevState: any = $state(null);
  let error = $state('');
  let lineMap: number[] = $state([]);
  let currentLine = $state(-1);
  let assembled = $state(false);

  let halted = $derived(state?.halted ?? false);

  async function handleAssemble() {
    error = '';
    try {
      const sim = await getSimulator();
      const map = sim.assemble_and_load(source);
      lineMap = map;
      prevState = null;
      state = sim.get_state();
      assembled = true;
      currentLine = lineMap[state.pc] ?? -1;
    } catch (e: any) {
      error = typeof e === 'string' ? e : e.message || String(e);
      assembled = false;
      state = null;
      prevState = null;
    }
  }

  async function handleStep() {
    error = '';
    try {
      const sim = await getSimulator();
      prevState = state;
      const result = sim.step();
      state = sim.get_state();
      currentLine = lineMap[state.pc] ?? -1;
    } catch (e: any) {
      error = typeof e === 'string' ? e : e.message || String(e);
    }
  }

  async function handleRun() {
    error = '';
    try {
      const sim = await getSimulator();
      let steps = 0;
      const maxSteps = 10000;
      while (steps < maxSteps) {
        prevState = state;
        const result = sim.step();
        state = sim.get_state();
        steps++;
        if (state.halted || state.dropped) break;
      }
      currentLine = lineMap[state.pc] ?? -1;
      if (steps >= maxSteps && !state.halted && !state.dropped) {
        error = `Stopped after ${maxSteps} steps (possible infinite loop)`;
      }
    } catch (e: any) {
      error = typeof e === 'string' ? e : e.message || String(e);
    }
  }

  async function handleReset() {
    error = '';
    try {
      const sim = await getSimulator();
      sim.reset();
      prevState = null;
      state = sim.get_state();
      currentLine = lineMap[state.pc] ?? -1;
    } catch (e: any) {
      error = typeof e === 'string' ? e : e.message || String(e);
    }
  }
</script>

<svelte:head>
  <link rel="stylesheet" href="/styles/playground.css" />
</svelte:head>

<div class="playground">
  <div class="panel-left">
    <Editor bind:source bind:currentLine />
    <Controls
      {assembled}
      {halted}
      onassemble={handleAssemble}
      onstep={handleStep}
      onrun={handleRun}
      onreset={handleReset}
    />
    {#if error}
      <div class="error-panel">{error}</div>
    {/if}
  </div>
  <div class="panel-right">
    <StateViewer {state} {prevState} />
  </div>
</div>
