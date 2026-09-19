# typed: strict
# frozen_string_literal: true

module Views
  module Scanner
    class Index < Views::Base
      extend T::Sig

      sig do
        params(
          active_scan_target: T.nilable(ScannerController::ActiveScanItemData),
          current_merchant: T.nilable(Merchant),
          merchants: T.nilable(T::Array[Merchant]),
          notice_flash: T.nilable(String),
          alert_flash: T.nilable(String)
        ).void
      end
      def initialize(active_scan_target:, current_merchant:, merchants:, notice_flash: nil, alert_flash: nil)
        @active_scan_target = T.let(active_scan_target, T.nilable(ScannerController::ActiveScanItemData))
        @current_merchant = T.let(current_merchant, T.nilable(Merchant))
        @merchants = T.let(merchants || [], T::Array[Merchant])
        @notice_flash = T.let(notice_flash, T.nilable(String))
        @alert_flash = T.let(alert_flash, T.nilable(String))
      end

      sig { void }
      def view_template
        m_id = @current_merchant ? @current_merchant.id : 1

        render Views::Layouts::ApplicationLayout.new(
          title: "PDA Mobile Barcode Scanner | Fashion Fulfillment OMS",
          current_merchant: @current_merchant,
          merchants: @merchants,
          current_path: scanner_path
        ) do
          div(class: "flex justify-center items-center py-6") do
            div(class: "pda-container w-full max-w-md bg-slate-900/95 border border-slate-800 rounded-3xl p-6 shadow-2xl") do
              render_pda_header
              render_target_card(m_id)
              render_camera_area
              render_flash_banners
              render_scan_form(m_id)
              render_bottom_link(m_id)
            end
          end

          render_scanner_script
        end
      end

      private

      sig { void }
      def render_pda_header
        merchant_name = @current_merchant ? @current_merchant.name : "Merchant"

        div(class: "flex items-center justify-between mb-6") do
          div(class: "flex items-center gap-3") do
            span(class: "text-2xl") { "📱" }
            div do
              h1(class: "text-xl font-extrabold text-white font-sans tracking-tight") { "PDA SCANNER MODE" }
              div(class: "text-xs font-mono text-indigo-400 font-bold") { merchant_name }
            end
          end

          button(
            type: "button",
            id: "beep-btn",
            class: "px-3 py-1 rounded-full text-xs font-semibold bg-emerald-500/15 border border-emerald-500/40 text-emerald-400 font-mono cursor-pointer flex items-center gap-1.5",
            data_action: "click->scanner#toggleBeep"
          ) do
            span { "🔊" }
            span(id: "beep-status") { "Auto-Beep" }
          end
        end
      end

      sig { params(m_id: Integer).void }
      def render_target_card(m_id)
        target = @active_scan_target

        if target
          diff_min = (((target.same_day_cutoff_at - Time.current) / 60).round)


          render Components::UI::Card.new(custom_class: "mb-6 border-indigo-500/40 border-l-4 border-l-indigo-500") do
            div(class: "flex items-center justify-between mb-3") do
              div(class: "font-mono text-lg font-bold text-white") { "##{target.order_number}" }
              div(class: "px-2.5 py-1 text-xs font-bold rounded-lg bg-rose-500/15 border border-rose-500/30 text-rose-400 font-mono") do
                "⏰ Due in #{diff_min}m"
              end
            end

            div(class: "p-3 rounded-lg bg-slate-950 border border-slate-800 mb-3 font-mono") do
              div(class: "text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-1") { "📍 TARGET RACK BIN" }
              div(class: "text-lg font-bold text-emerald-400") { target.bin_location.present? ? "📍 #{target.bin_location}" : "📍 no bin recorded" }
            end

            div(class: "flex items-center justify-between") do
              div do
                div(class: "text-xs font-mono text-slate-400 mt-0.5") do
                  "SKU: "
                  span(class: "text-indigo-400 font-bold") { target.sku }
                end
              end
              div(class: "px-3 py-1 rounded-lg bg-slate-800 border border-slate-700 text-white font-mono text-xs font-bold") do
                "1 / #{target.total_items_count}"
              end
            end
          end
        else
          render Components::UI::Card.new(custom_class: "mb-6 text-center py-8") do
            div(class: "text-3xl mb-2") { "📦" }
            div(class: "text-sm font-bold text-white font-sans mb-1") { "NO ORDER SELECTED FOR SCANNING" }
            div(class: "text-xs text-slate-400 mb-4") { "Please select an order from the Order Queue to start barcode picking & packing." }
            a(href: orders_path(merchant_id: m_id), class: "inline-flex items-center justify-center px-4 py-2 text-xs font-semibold rounded-lg bg-slate-800 hover:bg-slate-700 text-white border border-slate-700") do
              "← Select Order in Order Queue"
            end
          end
        end
      end

      sig { void }
      def render_camera_area
        div(class: "mb-4") do
          select(id: "camera-select", class: "w-full bg-slate-950 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500") do
            option(value: "") { "📷 Detecting Available Camera Devices..." }
          end
        end

        div(class: "w-full h-56 rounded-2xl bg-black border border-slate-800 flex flex-col items-center justify-center relative mb-6 overflow-hidden") do
          video(id: "camera-video", class: "w-full h-full object-cover block", playsinline: true, autoplay: true, muted: true)
          div(class: "w-52 h-28 border-2 border-dashed border-emerald-400/80 rounded-xl absolute flex items-center justify-center shadow-lg shadow-emerald-400/20 pointer-events-none") do
            span(class: "text-[10px] font-mono text-white/90 bg-black/70 px-2 py-0.5 rounded") { "ALIGN BARCODE HERE" }
          end
        end
      end

      sig { void }
      def render_flash_banners
        if @notice_flash.present?
          div(class: "p-3 mb-4 rounded-xl bg-emerald-500/10 border border-emerald-500/30 text-emerald-400 text-xs font-medium") do
            span { @notice_flash }
          end
        end

        if @alert_flash.present?
          div(class: "p-3 mb-4 rounded-xl bg-rose-500/10 border border-rose-500/30 text-rose-400 text-xs font-medium") do
            span { @alert_flash }
          end
        end
      end

      sig { params(m_id: Integer).void }
      def render_scan_form(m_id)
        target = @active_scan_target
        return unless target

        form(action: verify_scan_path(merchant_id: m_id), method: "post", id: "scan-form", class: "space-y-4 mb-6") do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          input(type: "hidden", name: "fulfillment_task_id", value: target.id.to_s)

          input(
            type: "text",
            name: "scanned_code",
            placeholder: "║█║ Scan SKU Barcode or Resi AWB...",
            autofocus: true,
            id: "barcode-input",
            class: "w-full bg-slate-950 border border-slate-800 rounded-xl px-4 py-3 text-sm text-white font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500"
          )

          input(type: "file", id: "image-file-input", accept: "image/*", class: "hidden")

          div(class: "flex items-center gap-2") do
            button(
              type: "button",
              class: "flex-1 px-3 py-2.5 text-xs font-semibold rounded-lg bg-slate-800 hover:bg-slate-700 text-white border border-slate-700 flex items-center justify-center gap-1.5",
              data_action: "click->scanner#initWebRTCCamera"
            ) do
              span { "📷" }
              span(id: "camera-btn-text") { "Start Camera" }
            end

            button(
              type: "button",
              class: "flex-1 px-3 py-2.5 text-xs font-semibold rounded-lg bg-slate-800 hover:bg-slate-700 text-white border border-slate-700 flex items-center justify-center gap-1.5",
              data_action: "click->scanner#triggerFileUpload"
            ) do
              span { "📁" }
              span { "Upload Image" }
            end

            render Components::UI::Button.new(variant: "primary", type: "submit", custom_class: "flex-1 text-xs py-2.5 font-bold") { "⚡ Verify" }
          end
        end
      end

      sig { params(m_id: Integer).void }
      def render_bottom_link(m_id)
        div(class: "text-center pt-4 border-t border-slate-800") do
          a(href: orders_path(merchant_id: m_id), class: "text-xs font-semibold text-slate-400 hover:text-white transition-colors inline-flex items-center gap-1.5") do
            "← Back to Order Queue"
          end
        end
      end

      sig { void }
      def render_scanner_script
        js_content = <<~JS
          let beepEnabled = true;
          let cameraStream = null;

          function toggleBeep() {
            beepEnabled = !beepEnabled;
            const statusEl = document.getElementById('beep-status');
            if (statusEl) statusEl.innerText = beepEnabled ? "Auto-Beep" : "Muted";
          }

          function playAudioTone(freq, duration) {
            if (!beepEnabled) return;
            try {
              const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
              const osc = audioCtx.createOscillator();
              const gain = audioCtx.createGain();
              osc.type = freq > 500 ? 'sine' : 'sawtooth';
              osc.frequency.setValueAtTime(freq, audioCtx.currentTime);
              osc.connect(gain);
              gain.connect(audioCtx.destination);
              osc.start();
              osc.stop(audioCtx.currentTime + duration);
            } catch (e) {
              console.log("AudioContext blocked or uninitialized", e);
            }
          }

          async function populateCameraDevices() {
            const selectEl = document.getElementById('camera-select');
            if (!selectEl) return;

            try {
              const devices = await navigator.mediaDevices.enumerateDevices();
              const videoInputs = devices.filter(d => d.kind === 'videoinput');

              selectEl.innerHTML = '';
              if (videoInputs.length === 0) {
                selectEl.innerHTML = '<option value="">📷 Default System Webcam</option>';
                return;
              }

              videoInputs.forEach((dev, idx) => {
                const opt = document.createElement('option');
                opt.value = dev.deviceId;
                opt.innerText = "📷 " + (dev.label || `Camera Device ${idx + 1}`);
                selectEl.appendChild(opt);
              });
            } catch (e) {
              selectEl.innerHTML = '<option value="">📷 Default System Webcam</option>';
            }
          }

          async function initWebRTCCamera(selectedDeviceId) {
            const videoEl = document.getElementById('camera-video');
            const btnText = document.getElementById('camera-btn-text');

            if (cameraStream && !selectedDeviceId) {
              cameraStream.getTracks().forEach(track => track.stop());
              cameraStream = null;
              if (videoEl) videoEl.srcObject = null;
              if (btnText) btnText.innerText = "Start Camera";
              return;
            }

            try {
              let constraints = { video: true };
              if (selectedDeviceId) {
                constraints = { video: { deviceId: { exact: selectedDeviceId } } };
              } else {
                const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
                constraints = isMobile ? { video: { facingMode: { ideal: "environment" } } } : { video: true };
              }

              cameraStream = await navigator.mediaDevices.getUserMedia(constraints);
              if (videoEl && cameraStream) {
                videoEl.srcObject = cameraStream;
                videoEl.play();
              }
              if (btnText) btnText.innerText = "Stop Camera";
              await populateCameraDevices();
            } catch (err) {
              console.error("Camera initialization error:", err);
            }
          }

          window.addEventListener('DOMContentLoaded', () => {
            populateCameraDevices();
            const notice = document.querySelector('.flash-banner.flash-notice');
            const alertMsg = document.querySelector('.flash-banner.flash-alert');
            if (notice) playAudioTone(880, 0.15);
            if (alertMsg) playAudioTone(220, 0.3);

            const input = document.getElementById('barcode-input');
            if (input) input.focus();
          });
        JS

        script do
          raw(ActiveSupport::SafeBuffer.new(js_content))
        end
      end
    end
  end
end
