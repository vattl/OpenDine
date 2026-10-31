package com.lanf.ai.solver;

import com.lanf.ai.dto.AiMenuSnapshotDTO;
import com.lanf.ai.dto.DinerMemberDTO;
import lombok.Data;

import java.util.List;

@Data
public class SolverInput {
    private int party_size;
    private int budget_fen;
    private String strategy; // balanced, budget_first, satiety_first, high_protein
    private List<String> table_goals;
    private List<DinerMemberDTO> members;
    private List<AiMenuSnapshotDTO.AiMenuItemDTO> menu_items;
    private String menu_version;
}
