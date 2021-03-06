defmodule BorsNG.Worker.AttemptorTest do
  use BorsNG.Worker.TestCase

  alias BorsNG.Worker.Attemptor
  alias BorsNG.Database.Attempt
  alias BorsNG.Database.AttemptStatus
  alias BorsNG.Database.Installation
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo
  alias BorsNG.GitHub

  setup do
    inst = %Installation{installation_xref: 91}
    |> Repo.insert!()
    proj = %Project{
      installation_id: inst.id,
      repo_xref: 14,
      staging_branch: "staging",
      trying_branch: "trying"}
    |> Repo.insert!()
    {:ok, inst: inst, proj: proj}
  end

  def new_patch(proj, pr_xref, commit) do
    %Patch{
      project_id: proj.id,
      pr_xref: pr_xref,
      into_branch: "master",
      commit: commit}
    |> Repo.insert!()
  end

  def new_attempt(patch, state) do
    %Attempt{patch_id: patch.id, state: state, into_branch: "master"}
    |> Repo.insert!()
  end

  test "rejects running patches", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{1 => []},
        statuses: %{},
        files: %{}
      }})
    patch = new_patch(proj, 1, nil)
    _attempt = new_attempt(patch, 0)
    Attemptor.handle_cast({:tried, patch.id, ""}, proj.id)
    state = GitHub.ServerMock.get_state()
    assert state == %{
      {{:installation, 91}, 14} => %{
        branches: %{},
        comments: %{
          1 => ["## try\n\nNot awaiting review"]
          },
        statuses: %{},
        files: %{}
      }}
  end

  test "infer from .travis.yml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying" => %{".travis.yml" => ""}}
      }})
    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    [status] = Repo.all(AttemptStatus)
    assert status.identifier == "continuous-integration/travis-ci/push"
  end

  test "infer from .travis.yml and appveyor.yml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying" => %{".travis.yml" => "", "appveyor.yml" => ""}}
      }})
    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    statuses = Repo.all(AttemptStatus)
    assert Enum.any?(statuses,
      &(&1.identifier == "continuous-integration/travis-ci/push"))
    assert Enum.any?(statuses,
      &(&1.identifier == "continuous-integration/appveyor/branch"))
  end

  test "infer from circle.yml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying" => %{"circle.yml" => ""}}
      }})
    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    [status] = Repo.all(AttemptStatus)
    assert status.identifier == "ci/circleci"
  end

  test "infer from jet-steps.yml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying" => %{"jet-steps.yml" => ""}}
      }})
    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    [status] = Repo.all(AttemptStatus)
    assert status.identifier == "continuous-integration/codeship"
  end

  test "infer from jet-steps.json", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying" => %{"jet-steps.json" => ""}}
      }})
    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    [status] = Repo.all(AttemptStatus)
    assert status.identifier == "continuous-integration/codeship"
  end

  test "infer from codeship-steps.yml", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying" => %{"codeship-steps.yml" => ""}}
      }})
    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    [status] = Repo.all(AttemptStatus)
    assert status.identifier == "continuous-integration/codeship"
  end

  test "infer from codeship-steps.json", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying" => %{"codeship-steps.json" => ""}}
      }})
    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    [status] = Repo.all(AttemptStatus)
    assert status.identifier == "continuous-integration/codeship"
  end

  test "full runthrough (with polling fallback)", %{proj: proj} do
    # Attempts start running immediately
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }})
    patch = new_patch(proj, 1, "N")
    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN"},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    attempt = Repo.get_by! Attempt, patch_id: patch.id
    assert attempt.state == 1
    # Polling should not change that.
    Attemptor.handle_info(:poll, proj.id)
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN"},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    attempt = Repo.get_by! Attempt, patch_id: patch.id
    assert attempt.state == 1
    # Mark the CI as having finished.
    # At this point, just running should still do nothing.
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN"},
        comments: %{1 => []},
        statuses: %{"iniN" => [{"ci", :ok}]},
        files: %{"trying" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }})
    Attemptor.handle_info(:poll, proj.id)
    attempt = Repo.get_by! Attempt, patch_id: patch.id
    assert attempt.state == 1
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN"},
        comments: %{1 => []},
        statuses: %{"iniN" => [{"ci", :ok}]},
        files: %{"trying" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
    # Finally, an actual poll should finish it.
    attempt
    |> Attempt.changeset(%{last_polled: 0})
    |> Repo.update!()
    Attemptor.handle_info(:poll, proj.id)
    attempt = Repo.get_by! Attempt, patch_id: patch.id
    assert attempt.state == 2
    assert GitHub.ServerMock.get_state() == %{
      {{:installation, 91}, 14} => %{
        branches: %{
          "master" => "ini",
          "trying" => "iniN"},
        comments: %{1 => ["## try\n\n# Build succeeded\n  * ci"]},
        statuses: %{"iniN" => [{"ci", :ok}]},
        files: %{"trying" => %{"bors.toml" => ~s/status = [ "ci" ]/}}
      }}
  end

  test "posts message if patch has ci skip", %{proj: proj} do
    GitHub.ServerMock.put_state(%{
      {{:installation, 91}, 14} => %{
        branches: %{"master" => "ini", "trying" => "", "trying.tmp" => ""},
        comments: %{1 => []},
        statuses: %{"iniN" => []},
        files: %{"trying" => %{"circle.yml" => ""}}
      }})
    patch = %Patch{
      project_id: proj.id,
      pr_xref: 1,
      commit: "N",
      title: "[ci skip]",
      into_branch: "master"}
    |> Repo.insert!()

    Attemptor.handle_cast({:tried, patch.id, "test"}, proj.id)
    state = GitHub.ServerMock.get_state()
    comments = state[{{:installation, 91}, 14}].comments[1]
    assert comments == ["## try\n\nHas [ci skip], bors build will time out"]
  end
end
