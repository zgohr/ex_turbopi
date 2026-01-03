defmodule BoardTest do
  use ExUnit.Case

  # Ensure modules are loaded before testing
  setup_all do
    Code.ensure_loaded!(Board)
    :ok
  end

  describe "mecanum kinematics" do
    test "drive function exists with default speed" do
      # drive/1 exists (with default speed)
      assert :erlang.function_exported(Board, :drive, 1)
    end

    test "drive function exists with explicit speed" do
      # drive/2 exists
      assert :erlang.function_exported(Board, :drive, 2)
    end

    test "mecanum_drive function exists" do
      assert :erlang.function_exported(Board, :mecanum_drive, 3)
    end

    test "stop function exists" do
      assert :erlang.function_exported(Board, :stop, 0)
    end
  end

  describe "API completeness" do
    test "RGB LED functions exist" do
      assert :erlang.function_exported(Board, :set_rgb, 4)
      assert :erlang.function_exported(Board, :set_board_rgb, 3)
      # rgb_off/1 with default, creates both /0 and /1
      assert :erlang.function_exported(Board, :rgb_off, 0)
      assert :erlang.function_exported(Board, :rgb_off, 1)
      assert :erlang.function_exported(Board, :board_rgb_off, 0)
    end

    test "servo functions exist" do
      # set_servo/3 with default creates /2 and /3
      assert :erlang.function_exported(Board, :set_servo, 2)
      assert :erlang.function_exported(Board, :set_servo, 3)
      # set_servos/2 with default creates /1 and /2
      assert :erlang.function_exported(Board, :set_servos, 1)
      assert :erlang.function_exported(Board, :set_servos, 2)
      assert :erlang.function_exported(Board, :center_gimbal, 0)
    end

    test "motor functions exist" do
      assert :erlang.function_exported(Board, :set_motor, 2)
      assert :erlang.function_exported(Board, :stop, 0)
      assert :erlang.function_exported(Board, :drive, 1)
      assert :erlang.function_exported(Board, :drive, 2)
      assert :erlang.function_exported(Board, :mecanum_drive, 3)
    end

    test "buzzer functions exist" do
      # beep/2 with defaults creates /0, /1, and /2
      assert :erlang.function_exported(Board, :beep, 0)
      assert :erlang.function_exported(Board, :beep, 1)
      assert :erlang.function_exported(Board, :beep, 2)
      assert :erlang.function_exported(Board, :buzzer_off, 0)
    end

    test "camera functions exist" do
      assert :erlang.function_exported(Board, :start_camera, 0)
      assert :erlang.function_exported(Board, :stop_camera, 0)
      assert :erlang.function_exported(Board, :camera_streaming?, 0)
      assert :erlang.function_exported(Board, :camera_stream_url, 0)
    end

    test "status functions exist" do
      assert :erlang.function_exported(Board, :connected?, 0)
      assert :erlang.function_exported(Board, :get_battery, 0)
    end
  end

  describe "camera_stream_url/0" do
    test "returns expected URL format" do
      url = Board.camera_stream_url()
      assert url =~ "http://"
      assert url =~ "/stream"
    end
  end
end
