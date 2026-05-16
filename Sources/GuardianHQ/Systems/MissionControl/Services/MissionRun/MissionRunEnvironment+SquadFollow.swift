import Foundation

extension MissionRunEnvironment {

    func isMissionRunRosterReleasedFromSquadFollow(assignmentID: UUID) -> Bool {
        missionRunRosterReleasedAssignmentIDs.contains(assignmentID)
    }

    /// RoE **SquadPromote**: wingman takes mission authority; remaining wingmen retarget convoy follow.
    @discardableResult
    func performSquadPromoteWingmanToPrimary(
        formerPrimaryAssignmentID: UUID,
        promotedWingmanAssignmentID: UUID,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        launchPrimaryMission: Bool = true
    ) -> Bool {
        attachServices(fleetLink: fleetLink, sitl: sitl, generalSettings: nil)
        systems.squadFollow.promoteWingmanToSquadPrimary(
            formerPrimaryAssignmentID: formerPrimaryAssignmentID,
            promotedWingmanAssignmentID: promotedWingmanAssignmentID,
            fleetLink: fleetLink,
            sitl: sitl,
            launchPrimaryWhenReady: false
        )
        guard launchPrimaryMission,
              let assignment = assignments.first(where: { $0.id == promotedWingmanAssignmentID }),
              let tokenKey = assignment.attachedFleetVehicleToken,
              !tokenKey.isEmpty
        else { return true }
        let issued = MissionRunIssuedCommand(
            assignmentID: promotedWingmanAssignmentID,
            slotName: assignment.slotName,
            vehicleTokenKey: tokenKey,
            dispatch: .catalogue(name: .fleetVehicleDoMissionStart, parameters: .empty),
            issuer: .missionControl,
            issuerKey: "missioncontrol.squad_follow.promote_wingman",
            category: .missionControl
        )
        appendEvent(systems.commands.dispatchCommand(issued, fleetLink: fleetLink, sitl: sitl))
        bumpSquadFollowStatusRevision()
        return true
    }

    /// RoE **RosterRelease**: stop wingman follow, optional park, retain slot on map as released.
    @discardableResult
    func performRosterReleaseWingmanFromSquadFollow(
        wingmanAssignmentID: UUID,
        primaryAssignmentID: UUID,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        dispatchPark: Bool = true
    ) -> Bool {
        attachServices(fleetLink: fleetLink, sitl: sitl, generalSettings: nil)
        systems.squadFollow.releaseWingmanFromSquadFollow(
            wingmanAssignmentID: wingmanAssignmentID,
            primaryAssignmentID: primaryAssignmentID,
            fleetLink: fleetLink
        )
        markMissionRunRosterReleasedFromSquadFollow(assignmentID: wingmanAssignmentID)
        bumpSquadFollowStatusRevision()
        guard dispatchPark,
              let assignment = assignments.first(where: { $0.id == wingmanAssignmentID }),
              let tokenKey = assignment.attachedFleetVehicleToken,
              !tokenKey.isEmpty
        else { return true }
        let issued = MissionRunIssuedCommand(
            assignmentID: wingmanAssignmentID,
            slotName: assignment.slotName,
            vehicleTokenKey: tokenKey,
            dispatch: .catalogue(name: .fleetVehicleDoPark, parameters: .empty),
            issuer: .missionControl,
            issuerKey: "missioncontrol.squad_follow.roster_release",
            category: .missionControl
        )
        appendEvent(systems.commands.dispatchCommand(issued, fleetLink: fleetLink, sitl: sitl))
        return true
    }
}
