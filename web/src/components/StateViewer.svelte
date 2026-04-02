<script lang="ts">
  let {
    state = null,
    prevState = null,
  }: {
    state: any;
    prevState: any;
  } = $props();

  function regChanged(regIndex: number): boolean {
    if (!prevState || !state) return false;
    return state.regs[regIndex] !== prevState.regs[regIndex];
  }

  function hexByte(value: number): string {
    return value.toString(16).toUpperCase().padStart(2, '0');
  }

  function hexPC(value: number): string {
    return '0x' + value.toString(16).toUpperCase().padStart(4, '0');
  }
</script>

{#if state}
  <div class="state-viewer">
    <div class="state-section">
      <h3>Registers</h3>
      <table class="reg-table">
        <thead>
          <tr><th>Name</th><th>Value</th></tr>
        </thead>
        <tbody>
          {#each state.regs as value, i}
            <tr>
              <td>PR{i}</td>
              <td class:changed={regChanged(i)}>{value}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>

    <div class="state-section">
      <h3>Status</h3>
      <div class="status-grid">
        <div class="status-item">
          <span class="status-label">PC</span>
          <span class="status-value">{hexPC(state.pc)}</span>
        </div>
        <div class="status-item">
          <span class="status-label">Step</span>
          <span class="status-value">{state.step_count}</span>
        </div>
        <div class="status-item">
          <span class="status-label">Cursor</span>
          <span class="status-value">{state.cursor}</span>
        </div>
        <div class="status-item">
          <span class="status-label">Halted</span>
          <span class="status-value">{state.halted ? 'Yes' : 'No'}</span>
        </div>
      </div>
    </div>

    <div class="state-section">
      <h3>Flags</h3>
      <div class="flags">
        <span class="flag" class:active={state.flag_z}>Z</span>
        <span class="flag" class:active={state.flag_n}>N</span>
      </div>
    </div>

    <div class="state-section">
      <h3>Packet Header</h3>
      <div class="hex-dump">
        {#each state.packet_header.slice(0, 64) as byte}
          <span class="hex-byte" class:nonzero={byte !== 0}>{hexByte(byte)}</span>
        {/each}
      </div>
    </div>
  </div>
{:else}
  <div class="state-placeholder">
    Assemble a program to see state.
  </div>
{/if}
