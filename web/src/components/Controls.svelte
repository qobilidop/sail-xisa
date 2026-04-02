<script lang="ts">
  let {
    assembled = false,
    halted = false,
    onassemble,
    onstep,
    onrun,
    onreset,
  }: {
    assembled: boolean;
    halted: boolean;
    onassemble: () => void;
    onstep: () => void;
    onrun: () => void;
    onreset: () => void;
  } = $props();
</script>

<div class="controls">
  <button class="btn btn-primary" onclick={onassemble}>Assemble</button>
  <button class="btn" disabled={!assembled || halted} onclick={onstep}>Step</button>
  <button class="btn" disabled={!assembled || halted} onclick={onrun}>Run</button>
  <button class="btn" disabled={!assembled} onclick={onreset}>Reset</button>
</div>
