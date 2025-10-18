import Foundation
import ArgumentParser

struct RenderWorkflow {
    let parameters: RenderParameters
    private let simulatorManager: SimulatorManaging

    init(parameters: RenderParameters, simulatorManager: SimulatorManaging = SimulatorManager()) {
        self.parameters = parameters
        self.simulatorManager = simulatorManager
    }

    func performDryRun() throws {
        let parser = RenderParameterParser(parameters: parameters)
        _ = try parser.sceneIdentifier()
        let statusOverride = StatusBarOverrideParser.parse(parameters.statusBar)
        let snippetInput = try parser.snippetInput(context: .dryRun)
        let externalDependencies = try parser.externalDependencies()

        let builder = RunnerBuilder()
        var context = RenderContext(
            parameters: parameters,
            snippetInput: snippetInput,
            builder: builder,
            launchConfiguration: nil,
            outputURL: nil,
            statusOverride: statusOverride,
            sceneID: nil,
            simulatorManager: simulatorManager,
            workspaceCleanupPolicy: .always,
            externalDependencies: externalDependencies
        )

        defer { finalizeContext(&context) }

        let steps: [RenderStepCommand] = [
            PrepareWorkspaceStep(),
            StageDependenciesStep(),
            ResolveDeviceStep(),
            BootDeviceStep(mode: .dryRun),
            ApplyStatusBarStep(mode: .dryRun)
        ]

        try execute(steps: steps, context: &context)
    }

    func performRender() throws {
        let parser = RenderParameterParser(parameters: parameters)
        let sceneID = try parser.sceneIdentifier()
        let statusOverride = StatusBarOverrideParser.parse(parameters.statusBar)
        let snippetInput = try parser.snippetInput(context: .render)
        let outputURL = try parser.outputURL()
        let externalDependencies = try parser.externalDependencies()

        let environmentBuilder = RenderEnvironmentBuilder(parameters: parameters)
        let launchConfiguration = try environmentBuilder.makeLaunchConfiguration(sceneID: sceneID, statusOverride: statusOverride)

        let builder = RunnerBuilder()
        var context = RenderContext(
            parameters: parameters,
            snippetInput: snippetInput,
            builder: builder,
            launchConfiguration: launchConfiguration,
            outputURL: outputURL,
            statusOverride: statusOverride,
            sceneID: sceneID,
            simulatorManager: simulatorManager,
            workspaceCleanupPolicy: .onSuccess,
            externalDependencies: externalDependencies
        )

        defer { finalizeContext(&context) }

        let steps: [RenderStepCommand] = [
            PrepareWorkspaceStep(),
            StageDependenciesStep(),
            ResolveDeviceStep(),
            BootDeviceStep(mode: .render),
            ApplyStatusBarStep(mode: .render),
            BuildRunnerStep(),
            InstallRunnerStep(),
            LaunchRunnerStep(),
            PullOutputStep(),
            ClearStatusBarStep(),
            CleanupWorkspaceStep()
        ]

        try execute(steps: steps, context: &context)
    }

    private func execute(steps: [RenderStepCommand], context: inout RenderContext) throws {
        do {
            for step in steps {
                try step.execute(context: &context)
            }
        } catch let workflowError as RenderWorkflowError {
            throw RenderErrorMapper.exitCode(for: workflowError)
        }
    }

    private func finalizeContext(_ context: inout RenderContext) {
        finalizeStatusBar(&context)
        finalizeWorkspace(&context)
    }

    private func finalizeStatusBar(_ context: inout RenderContext) {
        guard context.shouldClearStatusBar,
              !context.statusBarCleared,
              let device = context.resolvedDevice else { return }
        do {
            try context.simulatorManager.clearStatusBarOverride(udid: device.udid)
            IosSnapIO.printInfo("[sim] Cleared status bar override")
            context.shouldClearStatusBar = false
            context.statusBarCleared = true
        } catch let error as SimulatorManager.ManagerError {
            IosSnapIO.printError(describeSimulatorError(error))
        } catch {
            IosSnapIO.printError("[sim] Failed to clear status bar override: \(error.localizedDescription)")
        }
    }

    private func finalizeWorkspace(_ context: inout RenderContext) {
        guard let workspace = context.workspace else { return }
        switch context.workspaceCleanupPolicy {
        case .always:
            if !context.workspaceCleanupCompleted {
                workspace.cleanup()
                context.workspaceCleanupCompleted = true
            }
        case .onSuccess:
            if context.shouldCleanupWorkspace {
                if !context.workspaceCleanupCompleted {
                    workspace.cleanup()
                    context.workspaceCleanupCompleted = true
                }
            } else if !context.workspaceCleanupCompleted {
                let locationNote = workspace.isFallbackLocation ? " (fallback)" : ""
                IosSnapIO.printInfo("[build] Preserving runner workspace\(locationNote): \(workspace.rootURL.path)")
                context.workspaceCleanupCompleted = true
            }
        }
    }
}

// MARK: - Pipeline Context & Steps

private enum WorkspaceCleanupPolicy {
    case always
    case onSuccess
}

private struct RenderContext {
    let parameters: RenderParameters
    let snippetInput: RunnerBuilder.SnippetInput
    let builder: RunnerBuilder
    var launchConfiguration: RenderLaunchConfiguration?
    var outputURL: URL?
    let statusOverride: StatusBarOverride?
    let sceneID: String?
    let simulatorManager: SimulatorManaging
    var workspaceCleanupPolicy: WorkspaceCleanupPolicy
    var externalDependencies: ExternalDependenciesConfig?
    var buildOverrides: BuildSettingsOverrides? = nil
    var dependencyArtifacts: DependencyArtifacts? = nil

    var workspace: RunnerBuilder.Workspace?
    var resolvedDevice: SimulatorManager.ResolvedDevice?
    var runnerPipeline: RunnerPipeline?
    var appURL: URL?

    var shouldCleanupWorkspace: Bool = false
    var workspaceCleanupCompleted: Bool = false

    var shouldClearStatusBar: Bool = false
    var statusBarCleared: Bool = false

    var deviceBooted: Bool = false
}

private protocol RenderStepCommand {
    func execute(context: inout RenderContext) throws
}

private struct PrepareWorkspaceStep: RenderStepCommand {
    func execute(context: inout RenderContext) throws {
        do {
            let workspace = try context.builder.prepareWorkspace(input: context.snippetInput)
            context.workspace = workspace
            let locationNote = workspace.isFallbackLocation ? " (fallback)" : ""
            IosSnapIO.printInfo("[build] Prepared runner workspace\(locationNote): \(workspace.rootURL.path)")
        } catch let builderError as RunnerBuilder.BuilderError {
            IosSnapIO.printError("[build] \(builderError.description)")
            throw RenderWorkflowError.builder(builderError)
        }
    }
}

private struct StageDependenciesStep: RenderStepCommand {
    func execute(context: inout RenderContext) throws {
        guard let config = context.externalDependencies else { return }
        guard let workspace = context.workspace else {
            preconditionFailure("StageDependenciesStep requires a prepared workspace.")
        }

        guard config.hasAnyDependencies else {
            context.buildOverrides = nil
            context.dependencyArtifacts = nil
            return
        }

        if context.launchConfiguration == nil {
            IosSnapIO.printInfo("[deps] Skipping dependency build during dry-run.")
            context.buildOverrides = nil
            context.dependencyArtifacts = nil
            return
        }

        do {
            let builder = DependencyBuilder()
            let artifacts = try builder.stageDependencies(config: config, workspace: workspace)
            let overrides = artifacts.makeBuildOverrides()
            if ProcessInfo.processInfo.environment["IOS_SNAP_DEBUG_DEPS"] != nil {
                let lines = overrides?.asXcconfigLines() ?? []
                if !lines.isEmpty {
                    IosSnapIO.printInfo("[deps] build overrides: \(lines.joined(separator: " | "))")
                }
            }
            context.buildOverrides = overrides
            context.dependencyArtifacts = artifacts
        } catch let error as DependencyBuilder.BuilderError {
            IosSnapIO.printError("[deps] \(error.description)")
            throw RenderWorkflowError.dependencies(error)
        }
    }
}

private struct ResolveDeviceStep: RenderStepCommand {
    func execute(context: inout RenderContext) throws {
        do {
            let resolved = try context.simulatorManager.resolveDevice(udid: context.parameters.udid, deviceName: context.parameters.device)
            context.resolvedDevice = resolved
            IosSnapIO.printInfo("[sim] Resolved \(resolved.name) — \(resolved.udid) (\(resolved.runtime.displayName))")
        } catch let error as SimulatorManager.ManagerError {
            IosSnapIO.printError(describeSimulatorError(error))
            throw RenderWorkflowError.simulator(error)
        }
    }
}

private struct BootDeviceStep: RenderStepCommand {
    enum Mode {
        case dryRun
        case render
    }

    let mode: Mode

    func execute(context: inout RenderContext) throws {
        guard let device = context.resolvedDevice else { return }
        let shouldBoot: Bool
        switch mode {
        case .render:
            shouldBoot = true
        case .dryRun:
            shouldBoot = context.parameters.bootDevice || context.statusOverride != nil
        }
        guard shouldBoot else { return }

        do {
            try context.simulatorManager.bootIfNeeded(udid: device.udid)
            context.deviceBooted = true
            IosSnapIO.printInfo("[sim] Booted \(device.name)")
        } catch let error as SimulatorManager.ManagerError {
            IosSnapIO.printError(describeSimulatorError(error))
            throw RenderWorkflowError.simulator(error)
        }
    }
}

private struct ApplyStatusBarStep: RenderStepCommand {
    enum Mode {
        case dryRun
        case render
    }

    let mode: Mode

    func execute(context: inout RenderContext) throws {
        guard let override = context.statusOverride else { return }
        guard let device = context.resolvedDevice else { return }

        if mode == .dryRun && !context.deviceBooted {
            do {
                try context.simulatorManager.bootIfNeeded(udid: device.udid)
                context.deviceBooted = true
                IosSnapIO.printInfo("[sim] Booted \(device.name)")
            } catch let error as SimulatorManager.ManagerError {
                IosSnapIO.printError(describeSimulatorError(error))
                throw RenderWorkflowError.simulator(error)
            }
        }

        do {
            try context.simulatorManager.applyStatusBarOverride(udid: device.udid, override: override)
            IosSnapIO.printInfo("[sim] Applied status bar override")
        } catch let error as SimulatorManager.ManagerError {
            IosSnapIO.printError(describeSimulatorError(error))
            throw RenderWorkflowError.simulator(error)
        }

        switch mode {
        case .render:
            context.shouldClearStatusBar = true
        case .dryRun:
            do {
                try context.simulatorManager.clearStatusBarOverride(udid: device.udid)
                IosSnapIO.printInfo("[sim] Cleared status bar override")
                context.statusBarCleared = true
            } catch let error as SimulatorManager.ManagerError {
                IosSnapIO.printError(describeSimulatorError(error))
                throw RenderWorkflowError.simulator(error)
            }
        }
    }
}

private struct BuildRunnerStep: RenderStepCommand {
    func execute(context: inout RenderContext) throws {
        guard let workspace = context.workspace else {
            preconditionFailure("BuildRunnerStep requires a prepared workspace.")
        }
        guard let device = context.resolvedDevice else {
            preconditionFailure("BuildRunnerStep requires a resolved device.")
        }

        let pipeline = RunnerPipeline(
            workspace: workspace,
            device: device,
            buildOverrides: context.buildOverrides,
            dependencyArtifacts: context.dependencyArtifacts
        )
        context.runnerPipeline = pipeline

        do {
            let appURL = try pipeline.buildRunner()
            context.appURL = appURL
        } catch let error as RunnerPipeline.PipelineError {
            throw RenderWorkflowError.pipeline(error)
        }
    }
}

private struct InstallRunnerStep: RenderStepCommand {
    func execute(context: inout RenderContext) throws {
        guard let pipeline = context.runnerPipeline else {
            preconditionFailure("InstallRunnerStep requires an initialized runner pipeline.")
        }
        guard let appURL = context.appURL else {
            preconditionFailure("InstallRunnerStep requires a built Runner.app URL.")
        }

        do {
            try pipeline.installRunner(appURL: appURL)
        } catch let error as RunnerPipeline.PipelineError {
            throw RenderWorkflowError.pipeline(error)
        }
    }
}

private struct LaunchRunnerStep: RenderStepCommand {
    func execute(context: inout RenderContext) throws {
        guard let pipeline = context.runnerPipeline else {
            preconditionFailure("LaunchRunnerStep requires an initialized runner pipeline.")
        }
        guard let launchConfiguration = context.launchConfiguration else {
            preconditionFailure("LaunchRunnerStep requires a launch configuration.")
        }

        do {
            _ = try pipeline.launchRunner(environment: launchConfiguration.environment, arguments: launchConfiguration.arguments)
            IosSnapIO.printInfo("[run] Runner completed")
        } catch let error as RunnerPipeline.PipelineError {
            throw RenderWorkflowError.pipeline(error)
        }
    }
}

private struct PullOutputStep: RenderStepCommand {
    func execute(context: inout RenderContext) throws {
        guard let pipeline = context.runnerPipeline else {
            preconditionFailure("PullOutputStep requires an initialized runner pipeline.")
        }
        guard let outputURL = context.outputURL else {
            preconditionFailure("PullOutputStep requires an output URL.")
        }
        guard let launchConfiguration = context.launchConfiguration else {
            preconditionFailure("PullOutputStep requires a launch configuration.")
        }

        do {
            try pipeline.copyOutput(filename: launchConfiguration.outputFilename, to: outputURL)
            context.shouldCleanupWorkspace = true
        } catch let error as RunnerPipeline.PipelineError {
            throw RenderWorkflowError.pipeline(error)
        }
    }
}

private struct ClearStatusBarStep: RenderStepCommand {
    func execute(context: inout RenderContext) throws {
        guard context.shouldClearStatusBar else { return }
        guard let device = context.resolvedDevice else { return }

        do {
            try context.simulatorManager.clearStatusBarOverride(udid: device.udid)
            IosSnapIO.printInfo("[sim] Cleared status bar override")
            context.shouldClearStatusBar = false
            context.statusBarCleared = true
        } catch let error as SimulatorManager.ManagerError {
            IosSnapIO.printError(describeSimulatorError(error))
            throw RenderWorkflowError.simulator(error)
        }
    }
}

private struct CleanupWorkspaceStep: RenderStepCommand {
    func execute(context: inout RenderContext) throws {
        guard let workspace = context.workspace else { return }

        switch context.workspaceCleanupPolicy {
        case .always:
            workspace.cleanup()
            context.workspaceCleanupCompleted = true
        case .onSuccess:
            if context.shouldCleanupWorkspace {
                workspace.cleanup()
                context.workspaceCleanupCompleted = true
            } else {
                let locationNote = workspace.isFallbackLocation ? " (fallback)" : ""
                IosSnapIO.printInfo("[build] Preserving runner workspace\(locationNote): \(workspace.rootURL.path)")
                context.workspaceCleanupCompleted = true
            }
        }
    }
}
