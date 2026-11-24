"""
Collects close-out evidence.

Part of the AI-EFFECT Task 3.3 Danish node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
"""
from __future__ import annotations

from _support import (assert_baseline, docker, load_fixture, run_command, run_test, setting_path, write_csv)


def last_result(run_txt):
    if not run_txt.exists():
        return ""
    lines = [line for line in run_txt.read_text(encoding="utf-8", errors="replace").splitlines()
             if line.startswith("RESULT:")]
    return lines[-1] if lines else ""


def body(settings, evidence):
    commit = assert_baseline(settings)
    repo = setting_path(settings, "RepositoryRoot")
    evidence.save_text("commit.txt", commit + "\n")
    evidence.save_text("git-status.txt", run_command(["git", "-C", str(repo), "status", "--short"]).stdout)

    _, fixture_hash = load_fixture()
    evidence.save_text("fixture-sha256.txt", f"chp_dumploads.json {fixture_hash}\n")

    metadata = setting_path(settings, "DenmarkRoot") / "export" / "generation_metadata.json"
    if metadata.exists():
        evidence.save_text("export-generation-metadata.json", metadata.read_text(encoding="utf-8"))

    evidence.save_text("docker-ps.txt", docker("ps", "--format",
                                               "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}", timeout=60).stdout)
    evidence.save_text("docker-images.txt", docker("images", "--format",
                                                   "table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}", timeout=60).stdout)

    root = setting_path(settings, "EvidenceRoot")
    index = [{"EvidenceFolder": folder.name, "Result": last_result(folder / "run.txt")}
             for folder in sorted(p for p in root.iterdir() if p.is_dir() and p != evidence.path)]
    write_csv(evidence.file("evidence-index.csv"), index)
    for row in index:
        print(f"{row['EvidenceFolder']}: {row['Result']}")

    return "PASS", ("close-out saved the frozen baseline, fixture hash, export metadata, runtime inventory and "
                    f"an index of {len(index)} evidence folders.")


if __name__ == "__main__":
    run_test("99-closeout", body)
